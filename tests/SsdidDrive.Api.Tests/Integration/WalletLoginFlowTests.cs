using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;
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

        var signedChallenge = walletIdentity.SignChallenge(regChallenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId, signed_challenge = signedChallenge },
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

        // Step 2: Client subscribes to SSE (in background)
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var sseTask = ReadSseEvent(client, challengeId, cts.Token);

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

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var request = new HttpRequestMessage(HttpMethod.Get,
            $"/api/auth/ssdid/events?challenge_id={challengeId}");
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

    // --- Helper methods ---

    private (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateWalletIdentity()
    {
        var providers = new ICryptoProvider[] { new Ed25519Provider() };
        var cryptoFactory = new CryptoProviderFactory(providers);
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        return (identity, cryptoFactory);
    }

    private async Task<JsonElement> RegisterWallet(SsdidIdentity walletIdentity)
    {
        var client = _factory.CreateClient();

        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId }, SnakeJson);
        regResp.EnsureSuccessStatusCode();
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        var signedChallenge = walletIdentity.SignChallenge(challenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId, signed_challenge = signedChallenge },
            SnakeJson);
        verifyResp.EnsureSuccessStatusCode();
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        return verifyBody.GetProperty("credential");
    }

    private async Task<JsonElement?> ReadSseEvent(HttpClient client, string challengeId, CancellationToken ct)
    {
        var request = new HttpRequestMessage(HttpMethod.Get,
            $"/api/auth/ssdid/events?challenge_id={challengeId}");
        request.Headers.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));

        var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        while (!ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct);
            if (line is null) break;
            if (line.StartsWith("data: "))
            {
                var json = line["data: ".Length..];
                return JsonSerializer.Deserialize<JsonElement>(json);
            }
        }
        return null;
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
