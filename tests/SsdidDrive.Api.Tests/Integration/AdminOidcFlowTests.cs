using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using Ssdid.Sdk.Server.Session;
using OtpNet;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminOidcFlowTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public AdminOidcFlowTests(SsdidDriveFactory factory) => _factory = factory;

    // ── MFA Gate Tests ──

    [Fact]
    public async Task MfaPendingSession_AllowsTotpSetup()
    {
        var (client, _) = await CreateMfaPendingAdminAsync();

        var response = await client.PostAsync("/api/auth/totp/setup", null);

        // MFA gate should not block — expect 200 with TOTP secret
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.True(body.TryGetProperty("secret", out _));
    }

    [Fact]
    public async Task MfaPendingSession_AllowsTotpSetupConfirm()
    {
        var (client, _) = await CreateMfaPendingAdminAsync();

        var response = await client.PostAsJsonAsync("/api/auth/totp/setup/confirm", new { code = "000000" }, Json);

        // Should NOT be 403 "MFA verification required" — code validation error is expected
        Assert.NotEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task MfaPendingSession_BlocksOtherEndpoints()
    {
        var (client, _) = await CreateMfaPendingAdminAsync();

        var response = await client.GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Contains("MFA", body.GetProperty("detail").GetString()!);
    }

    [Fact]
    public async Task MfaPendingSession_TotpVerify_UpgradesToFullSession()
    {
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

        // Use TOTP verify to upgrade session (public endpoint, no auth header needed)
        var client = _factory.CreateClient();
        var totp = new Totp(Base32Encoding.ToBytes(secret));
        var code = totp.ComputeTotp();
        var verifyResp = await client.PostAsJsonAsync("/api/auth/totp/verify", new
        {
            email = user.Email,
            code
        }, Json);

        Assert.Equal(HttpStatusCode.OK, verifyResp.StatusCode);
        var body = await verifyResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var newToken = body.GetProperty("session_token").GetString();
        Assert.False(string.IsNullOrEmpty(newToken));

        // Verify the new session is NOT MFA-pending (can access /api/me)
        var meClient = _factory.CreateClient();
        meClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", newToken);
        var meResp = await meClient.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
    }

    // ── OidcAuthorize Tests ──

    [Fact]
    public async Task OidcAuthorize_Google_RedirectsToProvider()
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
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
        Assert.Contains("redirect_uri=", location);
    }

    [Fact]
    public async Task OidcAuthorize_Microsoft_RedirectsToProvider()
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var response = await client.GetAsync("/api/auth/oidc/microsoft/authorize");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.StartsWith("https://login.microsoftonline.com/common/oauth2/v2.0/authorize", location);
    }

    [Fact]
    public async Task OidcAuthorize_UnsupportedProvider_ReturnsBadRequest()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/auth/oidc/facebook/authorize");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task OidcAuthorize_ValidIosRedirectUri_Redirects()
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var response = await client.GetAsync(
            "/api/auth/oidc/google/authorize?redirect_uri=ssdid-drive://auth/callback");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", location);
    }

    [Fact]
    public async Task OidcAuthorize_ValidAndroidRedirectUri_Redirects()
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var response = await client.GetAsync(
            "/api/auth/oidc/google/authorize?redirect_uri=ssdiddrive://auth/callback");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", location);
    }

    [Fact]
    public async Task OidcAuthorize_MaliciousRedirectUri_Returns400()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync(
            "/api/auth/oidc/google/authorize?redirect_uri=https://evil.com");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task OidcAuthorize_JavascriptScheme_Returns400()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync(
            "/api/auth/oidc/google/authorize?redirect_uri=javascript://xss/payload");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task OidcAuthorize_NoRedirectUri_UsesDefault()
    {
        // When no redirect_uri is provided the authorize endpoint should still
        // redirect to the provider (redirect_uri stored as empty string in the
        // challenge; the callback falls back to the admin portal on completion).
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var response = await client.GetAsync("/api/auth/oidc/google/authorize");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var location = response.Headers.Location!.ToString();
        Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", location);

        // Verify that an empty redirect_uri is stored in the challenge payload
        var uri = new Uri(location);
        var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
        var state = query["state"]!;
        Assert.False(string.IsNullOrEmpty(state));

        using var scope = _factory.Services.CreateScope();
        var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
        var challenge = sessionStore.ConsumeChallenge("oidc", state);
        Assert.NotNull(challenge);

        // Format: "codeVerifier|redirect_uri|invitation_token"
        var parts = challenge.Challenge.Split('|');
        Assert.Equal(3, parts.Length);
        Assert.Equal(string.Empty, parts[1]); // no redirect_uri → empty
    }

    [Fact]
    public async Task OidcAuthorize_StoresStateInSessionStore()
    {
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var response = await client.GetAsync("/api/auth/oidc/google/authorize");
        var location = response.Headers.Location!.ToString();

        // Extract state from redirect URL
        var uri = new Uri(location);
        var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
        var state = query["state"];
        Assert.False(string.IsNullOrEmpty(state));

        // State should be URL-safe (no +, /, = chars)
        Assert.DoesNotContain("+", state);
        Assert.DoesNotContain("/", state);
        Assert.DoesNotContain("=", state);

        // Verify state is consumable from session store
        using var scope = _factory.Services.CreateScope();
        var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
        var challenge = sessionStore.ConsumeChallenge("oidc", state!);
        Assert.NotNull(challenge);
        Assert.Equal("google", challenge.KeyId);
        Assert.False(string.IsNullOrEmpty(challenge.Challenge)); // code verifier payload

        // Challenge is stored as "codeVerifier|redirect_uri|invitation_token"
        var codeVerifier = challenge.Challenge.Split('|')[0];
        var expectedChallenge = Convert.ToBase64String(
                SHA256.HashData(Encoding.ASCII.GetBytes(codeVerifier)))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var actualChallenge = query["code_challenge"];
        Assert.Equal(expectedChallenge, actualChallenge);
    }

    // ── OidcCallback Tests ──

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
    public async Task OidcCallback_ConsumedState_ReturnsUnauthorized()
    {
        // Get a valid state via authorize
        var noRedirectClient = _factory.CreateClient(new WebApplicationFactoryClientOptions
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

        // Try callback with consumed state
        var client = _factory.CreateClient();
        var response = await client.GetAsync($"/api/auth/oidc/google/callback?code=fake&state={state}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task OidcCallback_UnsupportedProvider_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();

        // With an invalid state, the callback returns Unauthorized before checking the provider
        var response = await client.GetAsync("/api/auth/oidc/facebook/callback?code=fake&state=fake");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task OidcCallback_CrossProviderState_ReturnsUnauthorized()
    {
        // Get a valid Google state token
        var noRedirectClient = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
        var authzResp = await noRedirectClient.GetAsync("/api/auth/oidc/google/authorize");
        var location = authzResp.Headers.Location!.ToString();
        var query = System.Web.HttpUtility.ParseQueryString(new Uri(location).Query);
        var googleState = query["state"]!;

        // Present the Google state to the Microsoft callback endpoint
        var client = _factory.CreateClient();
        var response = await client.GetAsync(
            $"/api/auth/oidc/microsoft/callback?code=fake-code&state={Uri.EscapeDataString(googleState)}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── Helpers ──

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

        CreateSessionDirect(sessionStore, $"mfa:{user.Id}", sessionToken);

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id);
    }

    private static void CreateSessionDirect(ISessionStore store, string value, string token)
    {
        switch (store)
        {
            case global::Ssdid.Sdk.Server.Session.InMemory.InMemorySessionStore inMemory:
                inMemory.CreateSessionDirect(value, token);
                break;
            case global::Ssdid.Sdk.Server.Session.Redis.RedisSessionStore redis:
                redis.CreateSessionDirect(value, token);
                break;
            default:
                throw new InvalidOperationException($"Unknown session store: {store.GetType().Name}");
        }
    }
}
