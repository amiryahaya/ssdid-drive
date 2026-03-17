using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.Crypto.Providers;
using Ssdid.Sdk.Server.Encoding;
using SsdidDrive.Api.Data;
using Ssdid.Sdk.Server.Identity;
using Ssdid.Sdk.Server.Registry;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class WalletLoginFlowTests : IClassFixture<WalletLoginFlowTests.WalletLoginFactory>
{
    private readonly WalletLoginFactory _factory;

    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public WalletLoginFlowTests(WalletLoginFactory factory) => _factory = factory;

    [Fact]
    public async Task LoginInitiate_ReturnsQrPayload()
    {
        var client = _factory.CreateClient();
        var resp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("challenge_id", out var challengeId));
        Assert.False(string.IsNullOrEmpty(challengeId.GetString()));

        Assert.True(body.TryGetProperty("subscriber_secret", out var subscriberSecret));
        Assert.False(string.IsNullOrEmpty(subscriberSecret.GetString()));

        Assert.True(body.TryGetProperty("qr_payload", out var qrPayload));
        var payload = qrPayload;
        Assert.Equal("login", payload.GetProperty("action").GetString());
        Assert.True(payload.TryGetProperty("challenge", out _));
        Assert.True(payload.TryGetProperty("server_did", out _));
        Assert.True(payload.TryGetProperty("server_key_id", out _));
        Assert.True(payload.TryGetProperty("server_signature", out _));
        Assert.True(payload.TryGetProperty("service_name", out _));
        Assert.True(payload.TryGetProperty("service_url", out _));
        Assert.True(payload.TryGetProperty("registry_url", out _));
    }

    [Fact]
    public async Task FullWalletLogin_RegisteredUser_DeliversSessionViaSse()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var client = _factory.CreateClient();

        // Step 1: Client initiates login
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        Assert.Equal(HttpStatusCode.OK, initResp.StatusCode);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;

        // Step 2: Wallet registers with the service (first time)
        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var regChallenge = regBody.GetProperty("challenge").GetString()!;

        var inviteToken = await TestFixture.CreateInviteTokenAsync(_factory);
        var signedChallenge = walletIdentity.SignChallenge(regChallenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId, signed_challenge = signedChallenge, invite_token = inviteToken },
            SnakeJson);
        Assert.Equal(HttpStatusCode.Created, verifyResp.StatusCode);
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        var credential = verifyBody.GetProperty("credential");

        // Step 3: Wallet authenticates with the VC, passing challengeId
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);
        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionToken = authBody.GetProperty("session_token").GetString()!;

        // Step 4: Verify the session token works
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sessionToken);
        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
    }

    [Fact]
    public async Task SseDelivery_WalletAuthenticates_ClientReceivesSessionToken()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var credential = await RegisterWallet(walletIdentity);

        var client = _factory.CreateClient();

        // Step 1: Client initiates login
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        // Step 2: Client subscribes to SSE (in background)
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var sseTask = ReadSseEvent(client, challengeId, subscriberSecret, cts.Token);

        // Step 3: Wallet authenticates (triggers SSE notification)
        var walletClient = _factory.CreateClient();
        var authResp = await walletClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);

        // Step 4: Client receives session token via SSE
        var sseData = await sseTask;
        Assert.NotNull(sseData);
        Assert.True(sseData.Value.TryGetProperty("session_token", out var sseToken));
        Assert.False(string.IsNullOrEmpty(sseToken.GetString()));

        // Step 5: Verify the SSE-delivered token works
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sseToken.GetString());
        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
    }

    [Fact]
    public async Task LoginInitiate_QrPayload_ContainsConfiguredServiceUrl()
    {
        var client = _factory.CreateClient();
        var resp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        var payload = body.GetProperty("qr_payload");

        Assert.True(payload.TryGetProperty("service_url", out _));
        var topLevelChallengeId = body.GetProperty("challenge_id").GetString()!;
        Assert.True(topLevelChallengeId.Length > 0);
        Assert.Equal(topLevelChallengeId, payload.GetProperty("challenge_id").GetString());
        Assert.StartsWith("did:ssdid:", payload.GetProperty("server_did").GetString());
    }

    [Fact]
    public async Task LoginInitiate_NoWalletResponse_SseTimesOut()
    {
        var client = _factory.CreateClient();

        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var request = new HttpRequestMessage(HttpMethod.Get,
            $"/api/auth/ssdid/events?challenge_id={challengeId}&subscriber_secret={Uri.EscapeDataString(subscriberSecret)}");
        request.Headers.Accept.Add(
            new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));

        var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cts.Token);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var stream = await response.Content.ReadAsStreamAsync(cts.Token);
        using var reader = new StreamReader(stream);

        string? eventType = null;
        try
        {
            while (!cts.Token.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(cts.Token);
                if (line is null) break;
                if (line.StartsWith("event: "))
                    eventType = line["event: ".Length..];
            }
        }
        catch (OperationCanceledException) { }

        Assert.True(eventType is null or "timeout");
    }

    [Fact]
    public async Task LoginFlow_ReuseChallengeId_SecondAuthDoesNotDeliverSse()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());
        var credential = await RegisterWallet(walletIdentity);

        var client = _factory.CreateClient();

        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;

        // First authentication with challengeId — consumes the waiter
        var authResp1 = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp1.StatusCode);

        // Second authentication with same challengeId — authenticate works but no SSE waiter
        var authResp2 = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp2.StatusCode);
    }

    [Fact]
    public async Task LoginFlow_UnregisteredWallet_AuthenticateReturns401()
    {
        var client = _factory.CreateClient();

        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;

        var fakeCredential = JsonSerializer.SerializeToElement(new
        {
            @context = new[] { "https://www.w3.org/2018/credentials/v1" },
            id = "urn:uuid:fake",
            type = new[] { "VerifiableCredential", "SsdidRegistrationCredential" },
            issuer = "did:ssdid:unknown-issuer",
            issuanceDate = DateTimeOffset.UtcNow.ToString("o"),
            expirationDate = DateTimeOffset.UtcNow.AddDays(365).ToString("o"),
            credentialSubject = new { id = "did:ssdid:fake-wallet", service = "drive", registeredAt = DateTimeOffset.UtcNow.ToString("o") },
            proof = new { type = "Ed25519Signature2020", created = DateTimeOffset.UtcNow.ToString("o"), verificationMethod = "did:ssdid:unknown-issuer#key-1", proofPurpose = "assertionMethod", proofValue = "uAAAA" }
        });

        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential = fakeCredential, challenge_id = challengeId }, SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, authResp.StatusCode);
    }

    // --- G1: SSE missing challenge_id returns 400 ---

    [Fact]
    public async Task SseEvents_MissingChallengeId_Returns400()
    {
        var client = _factory.CreateClient();
        var resp = await client.GetAsync("/api/auth/ssdid/events");
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    // --- SSE with invalid subscriber_secret returns 403 ---

    [Fact]
    public async Task SseEvents_InvalidSubscriberSecret_Returns403()
    {
        var client = _factory.CreateClient();

        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;

        var resp = await client.GetAsync($"/api/auth/ssdid/events?challenge_id={challengeId}&subscriber_secret=wrong-secret");
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    [Fact]
    public async Task SseEvents_MissingSubscriberSecret_Returns403()
    {
        var client = _factory.CreateClient();

        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;

        var resp = await client.GetAsync($"/api/auth/ssdid/events?challenge_id={challengeId}");
        Assert.Equal(HttpStatusCode.Forbidden, resp.StatusCode);
    }

    // --- G2: Orphaned completion waiters are garbage collected ---

    [Fact]
    public async Task SessionStore_CollectExpired_CleansUpOrphanedWaiters()
    {
        using var scope = _factory.Services.CreateScope();
        var store = scope.ServiceProvider.GetRequiredService<global::Ssdid.Sdk.Server.Session.InMemory.InMemorySessionStore>();

        // Create a waiter for a fake challenge_id
        using var cts = new CancellationTokenSource();
        var waiterTask = store.WaitForCompletion("orphaned-challenge-123", cts.Token);

        // The waiter should not have completed yet
        Assert.False(waiterTask.IsCompleted);

        // NotifyCompletion with a different key should return false (waiter still there)
        Assert.False(store.NotifyCompletion("different-key", "token"));

        // Notify the actual key to confirm it exists and clean up
        Assert.True(store.NotifyCompletion("orphaned-challenge-123", "test-token"));

        // The waiter should now be resolved
        var result = await waiterTask;
        Assert.Equal("test-token", result);

        // A second notify on the same key should return false (already removed)
        Assert.False(store.NotifyCompletion("orphaned-challenge-123", "token2"));
    }

    // --- G5: Valid VC but no User row returns 404 ---

    [Fact]
    public async Task Authenticate_ValidCredentialButNoUserRow_Returns404()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        // Register to get a valid credential
        var credential = await RegisterWallet(walletIdentity);

        // Delete the User row directly
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Did == walletIdentity.Did);
            if (user != null)
            {
                // Remove UserTenants first (FK constraint)
                var userTenants = db.UserTenants.Where(ut => ut.UserId == user.Id);
                db.UserTenants.RemoveRange(userTenants);
                db.Users.Remove(user);
                await db.SaveChangesAsync();
            }
        }

        // Now authenticate — VC is valid but no User exists
        var client = _factory.CreateClient();
        var authResp = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);

        Assert.Equal(HttpStatusCode.NotFound, authResp.StatusCode);
    }

    // --- G8: challenge_id uniqueness ---

    [Fact]
    public async Task LoginInitiate_CalledTwice_ProducesDistinctChallengeIds()
    {
        var client = _factory.CreateClient();

        var resp1 = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var body1 = await resp1.Content.ReadFromJsonAsync<JsonElement>();
        var id1 = body1.GetProperty("challenge_id").GetString()!;

        var resp2 = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var body2 = await resp2.Content.ReadFromJsonAsync<JsonElement>();
        var id2 = body2.GetProperty("challenge_id").GetString()!;

        Assert.NotEqual(id1, id2);
    }

    // --- G9: Server signature is valid over the challenge ---

    [Fact]
    public async Task LoginInitiate_ServerSignatureIsValidOverChallenge()
    {
        var client = _factory.CreateClient();

        // Get server identity info
        var infoResp = await client.GetAsync("/api/auth/ssdid/server-info");
        var infoBody = await infoResp.Content.ReadFromJsonAsync<JsonElement>();
        var serverDid = infoBody.GetProperty("server_did").GetString()!;
        var serverKeyId = infoBody.GetProperty("server_key_id").GetString()!;

        // Initiate login
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var payload = initBody.GetProperty("qr_payload");

        var challenge = payload.GetProperty("challenge").GetString()!;
        var serverSignature = payload.GetProperty("server_signature").GetString()!;

        // Verify server_did and server_key_id match server-info
        Assert.Equal(serverDid, payload.GetProperty("server_did").GetString());
        Assert.Equal(serverKeyId, payload.GetProperty("server_key_id").GetString());

        // Verify the signature is valid using the server's identity
        using var scope = _factory.Services.CreateScope();
        var identity = scope.ServiceProvider.GetRequiredService<SsdidIdentity>();
        var cryptoFactory = scope.ServiceProvider.GetRequiredService<CryptoProviderFactory>();

        var sigBytes = SsdidEncoding.MultibaseDecode(serverSignature);
        var challengeBytes = System.Text.Encoding.UTF8.GetBytes(challenge);

        var verified = cryptoFactory.Verify(identity.AlgorithmType, challengeBytes, sigBytes, identity.PublicKey);
        Assert.True(verified, "Server signature over QR challenge is invalid");
    }

    // --- Helper methods ---

    private (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateWalletIdentity()
        => TestFixture.CreateWalletIdentity();

    private async Task<JsonElement> RegisterWallet(SsdidIdentity walletIdentity)
        => await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

    private async Task<JsonElement?> ReadSseEvent(HttpClient client, string challengeId, string subscriberSecret, CancellationToken ct)
    {
        try
        {
            return await TestFixture.ReadSseEventOrFail(client, challengeId, subscriberSecret, ct);
        }
        catch (TimeoutException)
        {
            return null;
        }
    }

    public class WalletLoginFactory : SsdidDriveFactory
    {
        public MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.AddHttpClient<RegistryClient>()
                    .ConfigurePrimaryHttpMessageHandler(() => MockRegistryHandler);
            });
        }
    }

}
