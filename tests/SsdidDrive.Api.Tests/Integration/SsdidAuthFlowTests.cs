using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.Crypto.Providers;
using Ssdid.Sdk.Server.Encoding;
using Ssdid.Sdk.Server.Identity;
using Ssdid.Sdk.Server.Registry;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests for the full SSDID authentication flow:
/// ServerInfo → Register → RegisterVerify → Authenticate → Logout.
///
/// Uses a mock registry handler so RegistryClient returns controlled
/// DID Documents instead of hitting the real SSDID registry.
/// </summary>
public class SsdidAuthFlowTests : IClassFixture<SsdidAuthFlowTests.AuthFlowFactory>
{
    private readonly AuthFlowFactory _factory;

    // API uses snake_case serialization
    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public SsdidAuthFlowTests(AuthFlowFactory factory) => _factory = factory;

    // ── Test 1: Server Info ──

    [Fact]
    public async Task ServerInfo_ReturnsServerDidAndRegistryUrl()
    {
        var client = _factory.CreateClient();
        var resp = await client.GetAsync("/api/auth/ssdid/server-info");
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("server_did", out var did));
        Assert.StartsWith("did:ssdid:", did.GetString());
        Assert.True(body.TryGetProperty("server_key_id", out _));
        Assert.True(body.TryGetProperty("service_name", out _));
    }

    // ── Test 2: Register with unknown DID returns 404 ──

    [Fact]
    public async Task Register_UnknownDid_Returns404()
    {
        var client = _factory.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = "did:ssdid:unknown-client", key_id = "did:ssdid:unknown-client#key-1" },
            SnakeJson);

        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    // ── Test 3: Register with known DID returns challenge ──

    [Fact]
    public async Task Register_KnownDid_ReturnsChallenge()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);

        var client = _factory.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);

        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("challenge", out var challenge));
        Assert.False(string.IsNullOrEmpty(challenge.GetString()));
        Assert.True(body.TryGetProperty("server_did", out _));
        Assert.True(body.TryGetProperty("server_signature", out _));
    }

    // ── Test 4: RegisterVerify with valid signature returns credential ──

    [Fact]
    public async Task RegisterVerify_ValidSignature_ReturnsCredential()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);
        var inviteToken = await CreateInviteTokenAsync();

        var client = _factory.CreateClient();

        // Step 1: Register to get challenge
        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        // Step 2: Sign the challenge with client's private key
        var signedChallenge = clientIdentity.SignChallenge(challenge);

        // Step 3: Verify (with invite token)
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge, invite_token = inviteToken },
            SnakeJson);

        // RegisterVerify returns Created (201)
        Assert.Equal(HttpStatusCode.Created, verifyResp.StatusCode);

        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(verifyBody.TryGetProperty("credential", out var credential));
        // VC was serialized with default options (no snake_case), so keys are camelCase
        Assert.Equal("VerifiableCredential",
            credential.GetProperty("type")[0].GetString());
        Assert.Equal(clientIdentity.Did,
            credential.GetProperty("credentialSubject").GetProperty("id").GetString());
    }

    // ── Test 5: RegisterVerify with wrong signature returns 401 ──

    [Fact]
    public async Task RegisterVerify_WrongSignature_Returns401()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);

        var client = _factory.CreateClient();

        // Register to get challenge
        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();

        // Sign with garbage
        var fakeSignature = SsdidEncoding.MultibaseEncode(new byte[64]);

        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = fakeSignature },
            SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, verifyResp.StatusCode);
    }

    // ── Test 6: Authenticate with valid credential creates session ──

    [Fact]
    public async Task Authenticate_ValidCredential_ReturnsSession()
    {
        var credential = await ObtainCredential();

        var client = _factory.CreateClient();
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);

        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);

        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(authBody.TryGetProperty("session_token", out var token));
        Assert.False(string.IsNullOrEmpty(token.GetString()));
        Assert.True(authBody.TryGetProperty("server_signature", out _));
    }

    // ── Test 7: Session token from authenticate works for protected endpoints ──

    [Fact]
    public async Task SessionToken_GrantsAccessToProtectedEndpoints()
    {
        var credential = await ObtainCredential();

        var client = _factory.CreateClient();
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);
        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionToken = authBody.GetProperty("session_token").GetString()!;

        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sessionToken);

        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
    }

    // ── Test 8: Logout invalidates session from auth flow ──

    [Fact]
    public async Task Logout_InvalidatesAuthFlowSession()
    {
        var credential = await ObtainCredential();

        var client = _factory.CreateClient();
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);
        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionToken = authBody.GetProperty("session_token").GetString()!;

        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sessionToken);

        var before = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        var logout = await client.PostAsync("/api/auth/ssdid/logout", null);
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        var after = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }

    // ── Test 9: Replay challenge (consume twice) returns 401 ──

    [Fact]
    public async Task RegisterVerify_ReplayChallenge_Returns401()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);
        var inviteToken = await CreateInviteTokenAsync();

        var client = _factory.CreateClient();

        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;
        var signedChallenge = clientIdentity.SignChallenge(challenge);

        // First verify succeeds
        var verify1 = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge, invite_token = inviteToken },
            SnakeJson);
        Assert.Equal(HttpStatusCode.Created, verify1.StatusCode);

        // Second verify with same challenge fails (consumed)
        var verify2 = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge, invite_token = inviteToken },
            SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, verify2.StatusCode);
    }

    // ── Test 10: Authenticate with tampered credential returns 401 ──

    [Fact]
    public async Task Authenticate_TamperedCredential_Returns401()
    {
        var credential = await ObtainCredential();

        // Tamper: change the service field in credentialSubject
        var jsonStr = credential.GetRawText();
        var tampered = jsonStr.Replace("\"service\":\"drive\"", "\"service\":\"hacked\"");
        var tamperedElement = JsonSerializer.Deserialize<JsonElement>(tampered);

        var client = _factory.CreateClient();
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential = tamperedElement }, SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, authResp.StatusCode);
    }

    // ── Test 11: Register with mismatched keyId returns 401 on verify ──

    [Fact]
    public async Task RegisterVerify_MismatchedKeyId_Returns401()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);

        var client = _factory.CreateClient();

        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;
        var signedChallenge = clientIdentity.SignChallenge(challenge);

        // Verify with DIFFERENT keyId
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.Did + "#key-wrong", signed_challenge = signedChallenge },
            SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, verifyResp.StatusCode);
    }

    // ── Test 12: CanonicalJson produces sorted keys ──

    [Fact]
    public void CanonicalJson_SortsKeysAlphabetically()
    {
        var input = new Dictionary<string, object>
        {
            ["z"] = "last",
            ["a"] = "first",
            ["m"] = new Dictionary<string, object>
            {
                ["b"] = 2,
                ["a"] = 1
            }
        };

        var result = SsdidEncoding.CanonicalJson(input);
        Assert.Equal("{\"a\":\"first\",\"m\":{\"a\":1,\"b\":2},\"z\":\"last\"}", result);
    }

    // ── Test 13: W3C signing payload matches expected format ──

    [Fact]
    public void W3cSigningPayload_ProducesCorrectLength()
    {
        var doc = new Dictionary<string, object> { ["id"] = "did:ssdid:test" };
        var opts = new Dictionary<string, object> { ["type"] = "Ed25519Signature2020" };

        var payload = SsdidEncoding.W3cSigningPayload(doc, opts);

        // SHA3-256 produces 32 bytes each → 64 bytes total
        Assert.Equal(64, payload.Length);
    }

    // ── Test 14: DID Document @context serializes correctly ──

    [Fact]
    public void BuildDidDocument_HasAtContextKey()
    {
        var (identity, _) = CreateClientIdentity();

        var doc = identity.BuildDidDocument();
        Assert.True(doc.ContainsKey("@context"));

        var json = JsonSerializer.Serialize(doc);
        Assert.Contains("\"@context\"", json);
        Assert.DoesNotContain("\"context\":", json);
    }

    // ── Helpers ──

    private async Task<string> CreateInviteTokenAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = "Auth Test Tenant",
            Slug = $"auth-{Guid.NewGuid():N}"[..32],
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);

        var owner = new User
        {
            Id = Guid.NewGuid(),
            Did = $"did:ssdid:auth-owner-{Guid.NewGuid():N}",
            DisplayName = "Auth Owner",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Users.Add(owner);
        db.UserTenants.Add(new UserTenant
        {
            UserId = owner.Id,
            TenantId = tenant.Id,
            Role = TenantRole.Owner,
            CreatedAt = DateTimeOffset.UtcNow
        });

        var token = Convert.ToBase64String(Guid.NewGuid().ToByteArray())
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');
        db.Invitations.Add(new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenant.Id,
            InvitedById = owner.Id,
            Email = "test@example.com",
            Role = TenantRole.Member,
            Status = InvitationStatus.Pending,
            Token = token,
            ShortCode = $"TST-{Guid.NewGuid():N}"[..8].ToUpper(),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
        await db.SaveChangesAsync();
        return token;
    }

    private (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateClientIdentity()
    {
        var providers = new ICryptoProvider[] { new Ed25519Provider() };
        var cryptoFactory = new CryptoProviderFactory(providers);
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        return (identity, cryptoFactory);
    }

    private void RegisterClientInMockRegistry(SsdidIdentity identity)
    {
        var didDoc = identity.BuildDidDocument();
        _factory.MockRegistryHandler.RegisterDid(identity.Did, didDoc);
    }

    /// <summary>
    /// Runs the full register → verify flow and returns the issued credential.
    /// </summary>
    private async Task<JsonElement> ObtainCredential()
    {
        var (clientIdentity, _) = CreateClientIdentity();
        RegisterClientInMockRegistry(clientIdentity);
        var inviteToken = await CreateInviteTokenAsync();

        var client = _factory.CreateClient();

        // Register
        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        regResp.EnsureSuccessStatusCode();
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        // Sign & verify (with invite token)
        var signedChallenge = clientIdentity.SignChallenge(challenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge, invite_token = inviteToken },
            SnakeJson);
        verifyResp.EnsureSuccessStatusCode();
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        return verifyBody.GetProperty("credential");
    }

    // ── Test Factory with Mock Registry ──

    public class AuthFlowFactory : SsdidDriveFactory
    {
        public MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);

            builder.ConfigureServices(services =>
            {
                // Replace the RegistryClient's HttpClient handler with our mock
                services.AddHttpClient<RegistryClient>()
                    .ConfigurePrimaryHttpMessageHandler(() => MockRegistryHandler);
            });
        }
    }

}
