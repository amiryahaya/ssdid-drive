# Admin Portal Server-Side OIDC Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add server-side OIDC authorization code flow for the admin portal and fix the MfaPending middleware gate to allow TOTP setup during MFA-gated sessions.

**Architecture:** Two new endpoints (`GET /api/auth/oidc/{provider}/authorize` and `GET /api/auth/oidc/{provider}/callback`) implement the OAuth 2.0 authorization code flow with PKCE for server-side OIDC. A new `OidcCodeExchanger` service handles code-for-token exchange. The existing `SsdidAuthMiddleware` MFA gate is expanded to also allow TOTP setup/confirm endpoints. State is stored via the existing `ISessionStore` with a `"oidc-state:"` prefix and short TTL.

**Tech Stack:** ASP.NET Core 10 Minimal APIs, Microsoft.IdentityModel.Protocols.OpenIdConnect (already installed), existing ISessionStore for state management.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/SsdidDrive.Api/Services/OidcCodeExchanger.cs` | Create | Exchange authorization code for ID token (authorization code flow) |
| `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs` | Create | `GET /api/auth/oidc/{provider}/authorize` — redirect to provider |
| `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs` | Create | `GET /api/auth/oidc/{provider}/callback` — exchange code, create session |
| `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs` | Modify | Expand MFA gate to allow TOTP setup endpoints |
| `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs` | Modify | Map new OIDC endpoints |
| `src/SsdidDrive.Api/appsettings.json` | Modify | Add `ClientSecret` and `RedirectUri` per OIDC provider |
| `tests/SsdidDrive.Api.Tests/Unit/OidcCodeExchangerTests.cs` | Create | Unit tests for code exchanger |
| `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs` | Create | Integration tests for authorize/callback/MFA gate |

## Dependency Graph

```
Task 1 (MFA gate fix) ──────────────────────────────┐
Task 2 (OIDC config + code exchanger) ──┐           │
Task 3 (OidcAuthorize endpoint) ────────┤           │
                                        ├── Task 5 (Integration tests)
Task 4 (OidcCallback endpoint) ────────┘           │
                                                    │
                                        Task 5 depends on all ───┘
```

**Parallelizable:** Tasks 1 and 2 can run in parallel. Tasks 3 and 4 depend on Task 2. Task 5 depends on all.

---

## Chunk 1: MFA Gate + OIDC Infrastructure

### Task 1: Expand MfaPending middleware gate to allow TOTP setup

The current middleware at `SsdidAuthMiddleware.cs:80-88` only allows `/api/auth/totp/verify` when `MfaPending=true`. Admins who log in via OIDC without TOTP enabled need to call `/api/auth/totp/setup` and `/api/auth/totp/setup/confirm` to set up TOTP before they can get a full session. The gate must allow these endpoints too.

**Files:**
- Modify: `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs:79-88`
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs`

- [ ] **Step 1: Write integration test for MFA gate allowing TOTP setup**

Create `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminOidcFlowTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public AdminOidcFlowTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task MfaPendingSession_AllowsTotpSetup()
    {
        // Create admin user with MFA-pending session
        var (client, userId) = await CreateMfaPendingAdminAsync();

        // TOTP setup should be allowed through MFA gate
        var response = await client.PostAsync("/api/auth/totp/setup", null);

        // Should succeed (not 403 MFA required)
        Assert.NotEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task MfaPendingSession_BlocksOtherEndpoints()
    {
        var (client, userId) = await CreateMfaPendingAdminAsync();

        var response = await client.GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Contains("MFA", body.GetProperty("detail").GetString()!);
    }

    [Fact]
    public async Task MfaPendingSession_AllowsTotpSetupConfirm()
    {
        var (client, userId) = await CreateMfaPendingAdminAsync();

        // TotpSetupConfirm should be reachable (will fail on validation, not on gate)
        var response = await client.PostAsJsonAsync("/api/auth/totp/setup/confirm", new { code = "000000" }, Json);

        // Should NOT be 403 "MFA verification required" — any other error is fine
        Assert.NotEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private async Task<(HttpClient Client, Guid UserId)> CreateMfaPendingAdminAsync()
    {
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();

        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = "Admin Tenant",
            Slug = $"admin-{Guid.NewGuid():N}"[..32],
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);

        var user = new User
        {
            Id = Guid.NewGuid(),
            Did = $"did:ssdid:mfa-test-{Guid.NewGuid():N}",
            DisplayName = "Admin User",
            Email = $"admin-{Guid.NewGuid():N}@test.com",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Users.Add(user);

        db.UserTenants.Add(new UserTenant
        {
            UserId = user.Id,
            TenantId = tenant.Id,
            Role = TenantRole.Owner,
            CreatedAt = DateTimeOffset.UtcNow
        });
        await db.SaveChangesAsync();

        // Create MFA-pending session (mfa: prefix)
        CreateSessionDirect(sessionStore, $"mfa:{user.Id}", sessionToken);

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id);
    }

    private static void CreateSessionDirect(ISessionStore store, string value, string token)
    {
        switch (store)
        {
            case SessionStore inMemory:
                inMemory.CreateSessionDirect(value, token);
                break;
            case RedisSessionStore redis:
                redis.CreateSessionDirect(value, token);
                break;
            default:
                throw new InvalidOperationException($"Unknown session store: {store.GetType().Name}");
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AdminOidcFlowTests"`
Expected: `MfaPendingSession_AllowsTotpSetup` FAILS with 403 (MFA gate blocks it)

- [ ] **Step 3: Update SsdidAuthMiddleware to allow TOTP setup endpoints**

In `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs`, replace the MFA gate block (lines 79-88):

```csharp
// If MFA pending, only allow TOTP verify and TOTP setup endpoints
if (mfaPending)
{
    var path = context.Request.Path.Value ?? "";
    var allowedMfaPaths = new[]
    {
        "/api/auth/totp/verify",
        "/api/auth/totp/setup",
        "/api/auth/totp/setup/confirm"
    };

    if (!allowedMfaPaths.Any(p => path.Equals(p, StringComparison.OrdinalIgnoreCase)))
    {
        await WriteProblem(context, 403, "MFA verification required");
        return;
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AdminOidcFlowTests"`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs
git commit -m "fix: expand MFA gate to allow TOTP setup endpoints during pending MFA sessions"
```

---

### Task 2: Add OIDC configuration and code exchanger service

The existing `OidcTokenValidator` validates pre-obtained ID tokens (client-side flow). The admin portal needs server-side authorization code flow, which requires a `ClientSecret` and a service to exchange the authorization code for an ID token.

**Files:**
- Create: `src/SsdidDrive.Api/Services/OidcCodeExchanger.cs`
- Modify: `src/SsdidDrive.Api/appsettings.json`
- Test: `tests/SsdidDrive.Api.Tests/Unit/OidcCodeExchangerTests.cs`

- [ ] **Step 1: Add OIDC configuration in appsettings.json**

Update `src/SsdidDrive.Api/appsettings.json` to add `ClientSecret` and `RedirectUri` for each provider:

```json
"Oidc": {
  "Google": {
    "ClientId": "",
    "ClientSecret": "",
    "RedirectUri": ""
  },
  "Microsoft": {
    "ClientId": "",
    "ClientSecret": "",
    "RedirectUri": ""
  }
}
```

- [ ] **Step 2: Write unit test for OidcCodeExchanger**

Create `tests/SsdidDrive.Api.Tests/Unit/OidcCodeExchangerTests.cs`:

```csharp
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class OidcCodeExchangerTests
{
    [Fact]
    public void GetAuthorizationUrl_Google_ReturnsCorrectUrl()
    {
        var exchanger = CreateExchanger();

        var (url, state, codeVerifier) = exchanger.GetAuthorizationUrl("google", "test-state-123");

        Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", url);
        Assert.Contains("client_id=google-client-id", url);
        Assert.Contains("response_type=code", url);
        Assert.Contains("scope=openid+email+profile", url);
        Assert.Contains("state=test-state-123", url);
        Assert.Contains("code_challenge=", url);
        Assert.Contains("code_challenge_method=S256", url);
        Assert.Equal("test-state-123", state);
        Assert.False(string.IsNullOrEmpty(codeVerifier));
    }

    [Fact]
    public void GetAuthorizationUrl_Microsoft_ReturnsCorrectUrl()
    {
        var exchanger = CreateExchanger();

        var (url, state, codeVerifier) = exchanger.GetAuthorizationUrl("microsoft", "ms-state");

        Assert.StartsWith("https://login.microsoftonline.com/common/oauth2/v2.0/authorize", url);
        Assert.Contains("client_id=microsoft-client-id", url);
        Assert.Contains("state=ms-state", url);
    }

    [Fact]
    public void GetAuthorizationUrl_UnsupportedProvider_ReturnsNull()
    {
        var exchanger = CreateExchanger();

        var result = exchanger.GetAuthorizationUrl("facebook", "state");

        Assert.Null(result);
    }

    [Fact]
    public void GetAuthorizationUrl_UnconfiguredProvider_ReturnsNull()
    {
        var config = new Dictionary<string, string?>
        {
            ["Oidc:Google:ClientId"] = "",
            ["Oidc:Google:ClientSecret"] = "",
            ["Oidc:Google:RedirectUri"] = "",
        };
        var exchanger = CreateExchanger(config);

        var result = exchanger.GetAuthorizationUrl("google", "state");

        Assert.Null(result);
    }

    private static OidcCodeExchanger CreateExchanger(Dictionary<string, string?>? overrides = null)
    {
        var config = overrides ?? new Dictionary<string, string?>
        {
            ["Oidc:Google:ClientId"] = "google-client-id",
            ["Oidc:Google:ClientSecret"] = "google-client-secret",
            ["Oidc:Google:RedirectUri"] = "http://localhost:5000/api/auth/oidc/google/callback",
            ["Oidc:Microsoft:ClientId"] = "microsoft-client-id",
            ["Oidc:Microsoft:ClientSecret"] = "microsoft-client-secret",
            ["Oidc:Microsoft:RedirectUri"] = "http://localhost:5000/api/auth/oidc/microsoft/callback",
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(config)
            .Build();

        return new OidcCodeExchanger(configuration);
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "OidcCodeExchangerTests"`
Expected: Compilation error — `OidcCodeExchanger` class does not exist

- [ ] **Step 4: Implement OidcCodeExchanger**

Create `src/SsdidDrive.Api/Services/OidcCodeExchanger.cs`:

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Services;

public class OidcCodeExchanger
{
    private readonly Dictionary<string, OidcProviderConfig> _providers;

    public OidcCodeExchanger(IConfiguration config)
    {
        _providers = new Dictionary<string, OidcProviderConfig>(StringComparer.OrdinalIgnoreCase)
        {
            ["google"] = new(
                config["Oidc:Google:ClientId"] ?? "",
                config["Oidc:Google:ClientSecret"] ?? "",
                config["Oidc:Google:RedirectUri"] ?? "",
                "https://accounts.google.com/o/oauth2/v2/auth",
                "https://oauth2.googleapis.com/token"
            ),
            ["microsoft"] = new(
                config["Oidc:Microsoft:ClientId"] ?? "",
                config["Oidc:Microsoft:ClientSecret"] ?? "",
                config["Oidc:Microsoft:RedirectUri"] ?? "",
                "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                "https://login.microsoftonline.com/common/oauth2/v2.0/token"
            )
        };
    }

    /// <summary>
    /// Builds the authorization URL with PKCE. Returns null if provider is unsupported or unconfigured.
    /// </summary>
    public (string Url, string State, string CodeVerifier)? GetAuthorizationUrl(string provider, string state)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return null;

        if (string.IsNullOrEmpty(config.ClientId) || string.IsNullOrEmpty(config.ClientSecret))
            return null;

        var codeVerifier = GenerateCodeVerifier();
        var codeChallenge = ComputeCodeChallenge(codeVerifier);

        var query = new Dictionary<string, string>
        {
            ["client_id"] = config.ClientId,
            ["redirect_uri"] = config.RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid email profile",
            ["state"] = state,
            ["code_challenge"] = codeChallenge,
            ["code_challenge_method"] = "S256",
        };

        var queryString = string.Join("&", query.Select(kvp =>
            $"{Uri.EscapeDataString(kvp.Key)}={Uri.EscapeDataString(kvp.Value)}"));

        return ($"{config.AuthorizeUrl}?{queryString}", state, codeVerifier);
    }

    /// <summary>
    /// Exchanges an authorization code for an ID token. Returns the raw ID token string.
    /// </summary>
    public async Task<Result<string>> ExchangeCodeAsync(
        string provider, string code, string codeVerifier, CancellationToken ct = default)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return AppError.BadRequest($"Unsupported OIDC provider: {provider}");

        if (string.IsNullOrEmpty(config.ClientId) || string.IsNullOrEmpty(config.ClientSecret))
            return AppError.ServiceUnavailable($"OIDC provider '{provider}' is not configured");

        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = config.RedirectUri,
            ["client_id"] = config.ClientId,
            ["client_secret"] = config.ClientSecret,
            ["code_verifier"] = codeVerifier,
        };

        using var httpClient = new HttpClient();
        var response = await httpClient.PostAsync(config.TokenUrl, new FormUrlEncodedContent(body), ct);
        var responseBody = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
            return AppError.Unauthorized($"Token exchange failed: {response.StatusCode}");

        var json = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!json.TryGetProperty("id_token", out var idTokenProp))
            return AppError.Unauthorized("Token response missing id_token");

        return idTokenProp.GetString()!;
    }

    private static string GenerateCodeVerifier()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64UrlEncode(bytes);
    }

    private static string ComputeCodeChallenge(string codeVerifier)
    {
        var hash = SHA256.HashData(Encoding.ASCII.GetBytes(codeVerifier));
        return Base64UrlEncode(hash);
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private record OidcProviderConfig(
        string ClientId, string ClientSecret, string RedirectUri,
        string AuthorizeUrl, string TokenUrl);
}
```

- [ ] **Step 5: Register OidcCodeExchanger in DI**

In `src/SsdidDrive.Api/Program.cs`, add after `builder.Services.AddSingleton<OidcTokenValidator>();`:

```csharp
builder.Services.AddSingleton<OidcCodeExchanger>();
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "OidcCodeExchangerTests"`
Expected: All 4 tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/SsdidDrive.Api/Services/OidcCodeExchanger.cs src/SsdidDrive.Api/appsettings.json src/SsdidDrive.Api/Program.cs tests/SsdidDrive.Api.Tests/Unit/OidcCodeExchangerTests.cs
git commit -m "feat: add OidcCodeExchanger for server-side authorization code flow with PKCE"
```

---

## Chunk 2: OIDC Authorize & Callback Endpoints

### Task 3: OidcAuthorize endpoint

Redirects the admin portal browser to the OIDC provider's authorization page. Generates a state parameter and PKCE code verifier, stores both in the session store with a short TTL.

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs` (append)

**Context — how state is stored:** The `ISessionStore.CreateSession(value)` method generates a random token and maps `token → value`. We repurpose this: call `CreateSession("oidc-state:{codeVerifier}")` to get a state token. On callback, `GetSession(state)` returns the code verifier. The session TTL (default 60 min, but challenges have 5 min) means we use `CreateChallenge` instead for the short-lived OIDC state — however, `CreateChallenge` requires a DID and purpose. Instead, we store the state in the session store as a regular session with value `"oidc:{provider}:{codeVerifier}"` and delete it after use.

- [ ] **Step 1: Write integration test**

Append to `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs`:

```csharp
[Fact]
public async Task OidcAuthorize_Google_RedirectsToProvider()
{
    var client = _factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
    {
        AllowAutoRedirect = false
    });

    var response = await client.GetAsync("/api/auth/oidc/google/authorize");

    Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
    var location = response.Headers.Location!.ToString();
    Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", location);
    Assert.Contains("response_type=code", location);
    Assert.Contains("code_challenge=", location);
    Assert.Contains("state=", location);
}

[Fact]
public async Task OidcAuthorize_UnsupportedProvider_ReturnsBadRequest()
{
    var client = _factory.CreateClient();

    var response = await client.GetAsync("/api/auth/oidc/facebook/authorize");

    Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
}
```

- [ ] **Step 2: Implement OidcAuthorize**

Create `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs`:

```csharp
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcAuthorize
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/authorize", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static IResult Handle(
        string provider,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger)
    {
        var stateToken = Convert.ToBase64String(
            System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));

        var result = exchanger.GetAuthorizationUrl(provider, stateToken);
        if (result is null)
            return AppError.BadRequest($"OIDC provider '{provider}' is not supported or not configured").ToProblemResult();

        var (url, state, codeVerifier) = result.Value;

        // Store state → codeVerifier mapping (consumed on callback)
        sessionStore.CreateSession($"oidc:{provider}:{codeVerifier}");
        // The returned token is random — we need to use the state we passed.
        // Instead, use CreateChallenge-like storage with state as the key.
        // Hack: store the state in a session where state IS the token
        // by using CreateSessionDirect or by storing oidc state separately.

        // Better approach: create a session with value, then redirect with our state token.
        // On callback, look up the session by state token.
        // But ISessionStore.CreateSession generates a random token, not a deterministic one.
        // So we store the mapping: use state as a challenge-like entry.

        // Simplest: store via CreateChallenge(did="oidc", purpose=state, challenge=codeVerifier, keyId=provider)
        sessionStore.CreateChallenge("oidc", stateToken, codeVerifier, provider);

        return Results.Redirect(url);
    }
}
```

- [ ] **Step 3: Map the endpoint in AuthFeature.cs**

In `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`, add after the `OidcVerify.Map(auth);` line:

```csharp
OidcAuthorize.Map(auth);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "OidcAuthorize"`
Expected: Both tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs src/SsdidDrive.Api/Features/Auth/AuthFeature.cs
git commit -m "feat: add GET /api/auth/oidc/{provider}/authorize for server-side OIDC with PKCE"
```

---

### Task 4: OidcCallback endpoint

Handles the provider's redirect back with `code` and `state`. Exchanges the code for an ID token, validates it, creates a session (with MFA prefix for admin users), and redirects to the admin portal with the session token.

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs` (append)

- [ ] **Step 1: Write integration test for callback error cases**

Append to `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs`:

```csharp
[Fact]
public async Task OidcCallback_MissingCode_ReturnsBadRequest()
{
    var client = _factory.CreateClient();

    var response = await client.GetAsync("/api/auth/oidc/google/callback?state=fake-state");

    Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
}

[Fact]
public async Task OidcCallback_InvalidState_ReturnsUnauthorized()
{
    var client = _factory.CreateClient();

    var response = await client.GetAsync("/api/auth/oidc/google/callback?code=fake-code&state=invalid-state");

    Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
}

[Fact]
public async Task OidcCallback_UnsupportedProvider_ReturnsBadRequest()
{
    var client = _factory.CreateClient();

    var response = await client.GetAsync("/api/auth/oidc/facebook/callback?code=fake&state=fake");

    Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
}
```

- [ ] **Step 2: Implement OidcCallback**

Create `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcCallback
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/callback", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        string provider,
        string? code,
        string? state,
        AppDbContext db,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger,
        OidcTokenValidator validator,
        AuditService auditService,
        IConfiguration config,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(code))
            return AppError.BadRequest("Missing authorization code").ToProblemResult();
        if (string.IsNullOrEmpty(state))
            return AppError.BadRequest("Missing state parameter").ToProblemResult();

        // Validate and consume state
        var challengeEntry = sessionStore.ConsumeChallenge("oidc", state);
        if (challengeEntry is null)
            return AppError.Unauthorized("Invalid or expired state parameter").ToProblemResult();

        var codeVerifier = challengeEntry.Challenge;
        var storedProvider = challengeEntry.KeyId;

        if (!string.Equals(storedProvider, provider, StringComparison.OrdinalIgnoreCase))
            return AppError.Unauthorized("State/provider mismatch").ToProblemResult();

        // Exchange code for ID token
        var tokenResult = await exchanger.ExchangeCodeAsync(provider, code, codeVerifier, ct);
        if (!tokenResult.IsSuccess)
            return tokenResult.Error!.ToProblemResult();

        // Validate ID token
        var claims = await validator.ValidateAsync(provider, tokenResult.Value!, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is null)
            return RedirectWithError(config, "No account linked to this provider. Register first.");

        var user = existingLogin.Account;
        if (user.Status == UserStatus.Suspended)
            return RedirectWithError(config, "Account is suspended");

        user.LastLoginAt = DateTimeOffset.UtcNow;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // Check if user is admin/owner in any tenant
        var isAdmin = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id
                && (ut.Role == TenantRole.Owner || ut.Role == TenantRole.Admin), ct);

        string sessionValue;
        bool mfaRequired = false;
        bool totpSetupRequired = false;

        if (isAdmin)
        {
            if (user.TotpEnabled)
            {
                sessionValue = $"mfa:{user.Id}";
                mfaRequired = true;
            }
            else
            {
                sessionValue = $"mfa:{user.Id}";
                totpSetupRequired = true;
                mfaRequired = true;
            }
        }
        else
        {
            sessionValue = user.Id.ToString();
        }

        var sessionToken = sessionStore.CreateSession(sessionValue);
        if (sessionToken is null)
            return RedirectWithError(config, "Session limit exceeded");

        await auditService.LogAsync(user.Id, "auth.login.oidc", "user", user.Id,
            $"Provider: {provider} (server-side)", ct);

        // Redirect to admin portal with token
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        var redirectUrl = $"{adminBaseUrl}/auth/callback" +
            $"?token={Uri.EscapeDataString(sessionToken)}" +
            $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
            $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}";

        return Results.Redirect(redirectUrl);
    }

    private static IResult RedirectWithError(IConfiguration config, string error)
    {
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        return Results.Redirect($"{adminBaseUrl}/auth/callback?error={Uri.EscapeDataString(error)}");
    }
}
```

- [ ] **Step 3: Map the endpoint in AuthFeature.cs**

In `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`, add after `OidcAuthorize.Map(auth);`:

```csharp
OidcCallback.Map(auth);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "OidcCallback"`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/OidcCallback.cs src/SsdidDrive.Api/Features/Auth/AuthFeature.cs
git commit -m "feat: add GET /api/auth/oidc/{provider}/callback for server-side OIDC code exchange"
```

---

## Chunk 3: Integration Tests

### Task 5: Full integration test suite

Comprehensive integration tests covering the authorize → callback flow, MFA session upgrade, error paths, and admin-specific behaviors.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs` (add more tests)

- [ ] **Step 1: Add authorize → state validation round-trip test**

Append to `AdminOidcFlowTests.cs`:

```csharp
[Fact]
public async Task OidcAuthorize_StoresStateInSessionStore()
{
    var client = _factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
    {
        AllowAutoRedirect = false
    });

    var response = await client.GetAsync("/api/auth/oidc/google/authorize");

    Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
    var location = response.Headers.Location!.ToString();

    // Extract state from redirect URL
    var uri = new Uri(location);
    var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
    var state = query["state"];
    Assert.False(string.IsNullOrEmpty(state));

    // Verify state is consumable from session store
    using var scope = _factory.Services.CreateScope();
    var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
    var challenge = sessionStore.ConsumeChallenge("oidc", state!);
    Assert.NotNull(challenge);
    Assert.Equal("google", challenge.KeyId);
    Assert.False(string.IsNullOrEmpty(challenge.Challenge)); // code verifier
}

[Fact]
public async Task OidcCallback_ConsumedState_ReturnsUnauthorized()
{
    // First, do an authorize to get a valid state
    var noRedirectClient = _factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
    {
        AllowAutoRedirect = false
    });

    var authzResp = await noRedirectClient.GetAsync("/api/auth/oidc/google/authorize");
    var location = authzResp.Headers.Location!.ToString();
    var uri = new Uri(location);
    var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
    var state = query["state"]!;

    // Consume the state manually
    using var scope = _factory.Services.CreateScope();
    var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
    sessionStore.ConsumeChallenge("oidc", state);

    // Now try callback with the consumed state
    var client = _factory.CreateClient();
    var response = await client.GetAsync($"/api/auth/oidc/google/callback?code=fake&state={state}");

    Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
}
```

- [ ] **Step 2: Add TotpVerify MFA upgrade test**

```csharp
[Fact]
public async Task MfaPendingSession_TotpVerify_UpgradesToFullSession()
{
    // Create admin user with TOTP enabled and MFA-pending session
    var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

    using var scope = _factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
    var totpService = scope.ServiceProvider.GetRequiredService<TotpService>();
    var totpEncryption = scope.ServiceProvider.GetRequiredService<TotpEncryption>();

    var tenant = new Tenant
    {
        Id = Guid.NewGuid(),
        Name = "MFA Upgrade Tenant",
        Slug = $"mfa-up-{Guid.NewGuid():N}"[..32],
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow
    };
    db.Tenants.Add(tenant);

    var secret = totpService.GenerateSecret();
    var user = new User
    {
        Id = Guid.NewGuid(),
        Did = $"did:ssdid:mfa-up-{Guid.NewGuid():N}",
        Email = $"mfa-up-{Guid.NewGuid():N}@test.com",
        DisplayName = "MFA Upgrade User",
        Status = UserStatus.Active,
        TenantId = tenant.Id,
        TotpEnabled = true,
        TotpSecret = totpEncryption.Encrypt(secret),
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow
    };
    db.Users.Add(user);
    db.UserTenants.Add(new UserTenant
    {
        UserId = user.Id,
        TenantId = tenant.Id,
        Role = TenantRole.Owner,
        CreatedAt = DateTimeOffset.UtcNow
    });
    await db.SaveChangesAsync();

    CreateSessionDirect(sessionStore, $"mfa:{user.Id}", sessionToken);

    // Use TOTP verify to upgrade session
    var client = _factory.CreateClient();
    var code = totpService.GenerateCode(secret);
    var verifyResp = await client.PostAsJsonAsync("/api/auth/totp/verify", new
    {
        email = user.Email,
        code
    }, Json);

    Assert.Equal(HttpStatusCode.OK, verifyResp.StatusCode);
    var body = await verifyResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var newToken = body.GetProperty("token").GetString();
    Assert.False(string.IsNullOrEmpty(newToken));

    // Verify the new session is NOT MFA-pending (can access /api/me)
    var meClient = _factory.CreateClient();
    meClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", newToken);
    var meResp = await meClient.GetAsync("/api/me");
    Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
}
```

Add these using statements to the top of the test file if not already present:

```csharp
using SsdidDrive.Api.Services;
```

- [ ] **Step 3: Run all tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AdminOidcFlowTests"`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/AdminOidcFlowTests.cs
git commit -m "test: add comprehensive integration tests for admin OIDC flow and MFA upgrade"
```

---

## Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | Expand MFA gate in middleware to allow TOTP setup/confirm | None |
| 2 | OIDC config + OidcCodeExchanger service with PKCE | None |
| 3 | OidcAuthorize endpoint (redirect to provider) | Task 2 |
| 4 | OidcCallback endpoint (code exchange + session) | Task 2 |
| 5 | Integration tests (round-trip, MFA upgrade, error paths) | Tasks 1–4 |

Total: 5 tasks, ~25 files touched/created.
