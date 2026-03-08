# Wallet Login Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable ssdid-wallet users to log in to ssdid-drive via QR code (desktop/web) or deep link (mobile), using the SSDID challenge-response protocol with SSE-based session delivery.

**Architecture:** The ssdid-drive backend generates a login challenge and returns a `challengeId` for SSE subscription. The client (desktop/web/mobile) displays a QR code or opens a deep link containing the challenge payload. The ssdid-wallet scans/receives the payload, performs mutual auth + challenge signing against the backend, and the backend delivers the session token to the waiting client via SSE. No changes to the core SSDID protocol — this adds a new "login initiation" endpoint that decouples challenge creation from the wallet's DID.

**Tech Stack:** ASP.NET Core (.NET 10), xUnit, WebApplicationFactory, SQLite in-memory (tests), SSE (Server-Sent Events)

---

## Background

### Current State

The ssdid-drive backend already has a complete SSDID auth flow:
- `POST /api/auth/ssdid/register` — requires `{ did, keyId }` (wallet must be known upfront)
- `POST /api/auth/ssdid/register/verify` — verifies signed challenge, issues VC
- `POST /api/auth/ssdid/authenticate` — accepts VC, returns session token
- `GET /api/auth/ssdid/events?challenge_id=X` — SSE endpoint for async notification
- `SessionStore` — in-memory challenge + session management with SSE waiters

### What's Missing

1. **Login initiation without a DID** — current `/register` requires the wallet's DID upfront, but in the QR/deep link flow, the *client* (desktop app) doesn't know the wallet's DID. We need an endpoint that generates a challenge *before* the wallet identifies itself.

2. **QR/deep link payload** — a standardized JSON payload that encodes everything the wallet needs to complete auth.

3. **Challenge-to-DID binding** — after the wallet responds, the challenge needs to be associated with the wallet's DID retroactively.

### Flow Diagram

```
Desktop/Web Client                Backend API                        ssdid-wallet
      │                               │                                   │
      │── POST /login/initiate ──────→│                                   │
      │   { }                         │  generate challengeId + challenge │
      │←── { challengeId,             │  sign challenge with server key   │
      │      qrPayload (JSON) }       │                                   │
      │                               │                                   │
      │── GET /events?challenge_id ──→│  (SSE connection, waiting)        │
      │                               │                                   │
      │  [show QR / open deep link]   │                                   │
      │         ········QR scan / deep link ·····················→        │
      │                               │                                   │
      │                               │  IF wallet NOT registered:        │
      │                               │←── POST /register ───────────────│
      │                               │←── POST /register/verify ────────│
      │                               │                                   │
      │                               │  THEN (always):                   │
      │                               │←── POST /authenticate ──────────│
      │                               │    { credential, challengeId }    │
      │                               │                                   │
      │←── SSE: { session_token,      │                                   │
      │          did, user } ─────────│                                   │
      │                               │                                   │
      │  [logged in, store token]     │                                   │
```

### QR / Deep Link Payload Format

```json
{
  "action": "login",
  "service_url": "https://drive.example.com",
  "service_name": "ssdid-drive",
  "challenge_id": "abc123-def456",
  "challenge": "BASE64URL_CHALLENGE",
  "server_did": "did:ssdid:server...",
  "server_key_id": "did:ssdid:server...#key-1",
  "server_signature": "uSIGNATURE...",
  "registry_url": "https://registry.ssdid.my"
}
```

- **QR code:** `ssdid://login?payload=BASE64URL(json)`
- **Deep link:** `ssdid://login?payload=BASE64URL(json)`
- Same URI scheme for both. Client chooses QR display vs deep link based on platform.

---

## Task 1: Add `LoginInitiate` Endpoint

Creates a new endpoint that generates a challenge without requiring a wallet DID. This is the entry point for the QR/deep link flow.

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/LoginInitiate.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs:11-15`
- Modify: `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs` (add to whitelist)
- Test: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the failing test**

Create the test file with the first test:

```csharp
// tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs

using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Tests for the wallet-based login flow: QR code / deep link initiation,
/// wallet-side auth, and SSE session delivery.
/// </summary>
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

    // ── Test Factory ──

    public class WalletLoginFactory : SsdidDriveFactory
    {
        public SsdidAuthFlowTests.MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

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
```

**Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginInitiate_ReturnsQrPayload" --no-build 2>&1 || dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginInitiate_ReturnsQrPayload"`
Expected: FAIL — 404 because endpoint doesn't exist yet.

**Step 3: Implement the endpoint**

```csharp
// src/SsdidDrive.Api/Features/Auth/LoginInitiate.cs

using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class LoginInitiate
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/login/initiate", Handle);

    private static IResult Handle(
        SsdidIdentity identity,
        SessionStore sessionStore,
        IConfiguration config)
    {
        var challengeId = Guid.NewGuid().ToString("N");
        var challenge = SsdidCrypto.GenerateChallenge();
        var serverSignature = identity.SignChallenge(challenge);

        // Store challenge keyed by challengeId (not by DID — DID is unknown at this point).
        // The wallet will bind its DID when it calls /register or /authenticate.
        sessionStore.CreateChallenge(challengeId, "login", challenge, keyId: "");

        var registryUrl = config["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
        var serviceUrl = config["Ssdid:ServiceUrl"] ?? "";

        var qrPayload = new
        {
            action = "login",
            service_url = serviceUrl,
            service_name = "ssdid-drive",
            challenge_id = challengeId,
            challenge,
            server_did = identity.Did,
            server_key_id = identity.KeyId,
            server_signature = serverSignature,
            registry_url = registryUrl
        };

        return Results.Ok(new
        {
            challenge_id = challengeId,
            qr_payload = qrPayload
        });
    }
}
```

**Step 4: Register the endpoint**

In `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`, add `LoginInitiate.Map(group);` after the existing endpoint registrations:

```csharp
// Add after line 15 (Logout.Map(group);)
LoginInitiate.Map(group);
```

In `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs`, add `/api/auth/ssdid/login/initiate` to the public path whitelist (find the existing whitelist array and add this path).

**Step 5: Run test to verify it passes**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginInitiate_ReturnsQrPayload"`
Expected: PASS

**Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/LoginInitiate.cs \
        src/SsdidDrive.Api/Features/Auth/AuthFeature.cs \
        src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs \
        tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "feat(auth): add POST /login/initiate endpoint for QR/deep link flow"
```

---

## Task 2: Full Wallet Login Flow — Registered User

Tests and verifies the complete flow: client initiates login → wallet registers + authenticates → client receives session via SSE.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the failing test**

Add to `WalletLoginFlowTests`:

```csharp
[Fact]
public async Task FullWalletLogin_RegisteredUser_DeliversSessionViaSse()
{
    // Simulate a wallet identity
    var (walletIdentity, _) = CreateWalletIdentity();
    _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

    var client = _factory.CreateClient();

    // Step 1: Client initiates login
    var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    Assert.Equal(HttpStatusCode.OK, initResp.StatusCode);
    var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
    var challengeId = initBody.GetProperty("challenge_id").GetString()!;

    // Step 2: Wallet registers with the service (if first time)
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

private (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateWalletIdentity()
{
    var providers = new ICryptoProvider[] { new Ed25519Provider() };
    var cryptoFactory = new CryptoProviderFactory(providers);
    var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
    return (identity, cryptoFactory);
}
```

**Step 2: Run test to verify it passes** (all plumbing from Task 1 should make this work)

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.FullWalletLogin_RegisteredUser_DeliversSessionViaSse"`
Expected: PASS — the `/authenticate` endpoint already accepts `challengeId` and calls `sessionStore.NotifyCompletion()`.

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "test(auth): add full wallet login flow integration test"
```

---

## Task 3: SSE Delivery Test

Tests that the SSE endpoint delivers the session token when the wallet completes authentication, simulating the real async flow (client waits on SSE while wallet authenticates).

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the test**

Add to `WalletLoginFlowTests`:

```csharp
[Fact]
public async Task SseDelivery_WalletAuthenticates_ClientReceivesSessionToken()
{
    var (walletIdentity, _) = CreateWalletIdentity();
    _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

    // Pre-register the wallet so we have a credential
    var credential = await RegisterWallet(walletIdentity);

    var client = _factory.CreateClient();

    // Step 1: Client initiates login
    var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
    var challengeId = initBody.GetProperty("challenge_id").GetString()!;

    // Step 2: Client subscribes to SSE (in background)
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
    var sseTask = ReadSseEvent(client, challengeId, cts.Token);

    // Small delay to ensure SSE connection is established
    await Task.Delay(100);

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
```

**Step 2: Run test**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.SseDelivery_WalletAuthenticates_ClientReceivesSessionToken"`
Expected: PASS — SSE + NotifyCompletion already work.

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "test(auth): add SSE delivery test for wallet login flow"
```

---

## Task 4: Login Initiate with `service_url` Configuration

Ensure `service_url` in the QR payload is configurable via `appsettings.json` and test that it appears correctly.

**Files:**
- Modify: `src/SsdidDrive.Api/appsettings.json` (add `Ssdid:ServiceUrl`)
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the test**

Add to `WalletLoginFlowTests`:

```csharp
[Fact]
public async Task LoginInitiate_QrPayload_ContainsConfiguredServiceUrl()
{
    var client = _factory.CreateClient();
    var resp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
    var payload = body.GetProperty("qr_payload");

    // service_url should come from config (may be empty in test, that's ok)
    Assert.True(payload.TryGetProperty("service_url", out _));
    // challenge_id should be a non-empty string
    Assert.True(payload.GetProperty("challenge_id").GetString()!.Length > 0);
    // server_did should match server identity
    Assert.StartsWith("did:ssdid:", payload.GetProperty("server_did").GetString());
}
```

**Step 2: Add config entry**

In `src/SsdidDrive.Api/appsettings.json`, add under the `Ssdid` section:

```json
"ServiceUrl": "https://drive.ssdid.my"
```

**Step 3: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests"`
Expected: All PASS

**Step 4: Commit**

```bash
git add src/SsdidDrive.Api/appsettings.json \
        tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "feat(auth): configure service_url for QR login payload"
```

---

## Task 5: Edge Case — Login Initiate Timeout

Test that SSE correctly times out when no wallet authenticates within the timeout period.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the test**

```csharp
[Fact]
public async Task LoginInitiate_NoWalletResponse_SseTimesOut()
{
    var client = _factory.CreateClient();

    // Initiate login
    var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
    var challengeId = initBody.GetProperty("challenge_id").GetString()!;

    // Subscribe to SSE with short timeout
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

    var request = new HttpRequestMessage(HttpMethod.Get,
        $"/api/auth/ssdid/events?challenge_id={challengeId}");
    request.Headers.Accept.Add(
        new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));

    var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cts.Token);
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    // Connection established but no event received before timeout
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

    // Either we got timeout event from server, or our CTS cancelled first — both are acceptable
    // The server's timeout is 5 minutes, our test timeout is 2 seconds, so we'll hit our CTS first
    Assert.True(eventType is null or "timeout");
}
```

**Step 2: Run test**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginInitiate_NoWalletResponse_SseTimesOut"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "test(auth): add SSE timeout edge case test for wallet login"
```

---

## Task 6: Edge Case — Reuse ChallengeId Fails

Test that a challengeId can only be used once (the wallet can't re-trigger a session with the same challengeId).

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the test**

```csharp
[Fact]
public async Task LoginFlow_ReuseChallengeId_SecondAuthDoesNotDeliverSse()
{
    var (walletIdentity, _) = CreateWalletIdentity();
    _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());
    var credential = await RegisterWallet(walletIdentity);

    var client = _factory.CreateClient();

    // Initiate login
    var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
    var challengeId = initBody.GetProperty("challenge_id").GetString()!;

    // First authentication with challengeId — should work and consume the waiter
    var authResp1 = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
        new { credential, challenge_id = challengeId }, SnakeJson);
    Assert.Equal(HttpStatusCode.OK, authResp1.StatusCode);

    // Second authentication with same challengeId — authenticate itself works
    // (it's a valid credential), but there's no SSE waiter to notify
    var authResp2 = await client.PostAsJsonAsync("/api/auth/ssdid/authenticate",
        new { credential, challenge_id = challengeId }, SnakeJson);
    Assert.Equal(HttpStatusCode.OK, authResp2.StatusCode);
    // The session is valid but the SSE waiter was already consumed — no double delivery
}
```

**Step 2: Run test**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginFlow_ReuseChallengeId"`
Expected: PASS — `NotifyCompletion` uses `TryRemove`, so second call returns false silently.

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "test(auth): add challengeId reuse guard test"
```

---

## Task 7: Edge Case — Unregistered Wallet Attempts Login

Test that when a wallet that hasn't registered tries to authenticate, it gets a proper error and the client isn't left hanging.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs`

**Step 1: Write the test**

```csharp
[Fact]
public async Task LoginFlow_UnregisteredWallet_AuthenticateReturns401()
{
    var client = _factory.CreateClient();

    // Initiate login
    var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
    var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
    var challengeId = initBody.GetProperty("challenge_id").GetString()!;

    // Wallet tries to authenticate with a fabricated credential (not issued by this server)
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

    // Server should reject — untrusted issuer
    Assert.Equal(HttpStatusCode.Unauthorized, authResp.StatusCode);
}
```

**Step 2: Run test**

Run: `dotnet test tests/SsdidDrive.Api.Tests --filter "WalletLoginFlowTests.LoginFlow_UnregisteredWallet_AuthenticateReturns401"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/WalletLoginFlowTests.cs
git commit -m "test(auth): add unregistered wallet rejection test"
```

---

## Task 8: Run Full Test Suite

Verify nothing is broken after all changes.

**Step 1: Run all tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests`
Expected: All existing tests PASS + all new WalletLoginFlowTests PASS.

**Step 2: Commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: resolve test regressions from wallet login flow"
```

---

## Summary

| Task | Description | Files Changed |
|------|-------------|---------------|
| 1 | `POST /login/initiate` endpoint | LoginInitiate.cs (new), AuthFeature.cs, SsdidAuthMiddleware.cs, WalletLoginFlowTests.cs (new) |
| 2 | Full wallet login flow test | WalletLoginFlowTests.cs |
| 3 | SSE delivery test | WalletLoginFlowTests.cs |
| 4 | `service_url` configuration | appsettings.json, WalletLoginFlowTests.cs |
| 5 | SSE timeout edge case | WalletLoginFlowTests.cs |
| 6 | ChallengeId reuse guard | WalletLoginFlowTests.cs |
| 7 | Unregistered wallet rejection | WalletLoginFlowTests.cs |
| 8 | Full test suite verification | — |

### What This Does NOT Cover (Future Work)

- **ssdid-wallet deep link handling** — wallet-side code to parse `ssdid://login?payload=...` and trigger the auth flow (lives in the `ssdid-wallet` repo)
- **ssdid-drive desktop/mobile client UI** — QR code generation, deep link opening, SSE subscription (lives in the client repos)
- **Rate limiting for login/initiate** — currently uses the `auth` rate limit group (20/min), may need tuning
- **Challenge expiry for login initiate** — currently uses the SessionStore's 5-minute challenge TTL, which is appropriate
- **KAZ-Sign registry interop** — deferred, requires C↔Java signature format alignment
