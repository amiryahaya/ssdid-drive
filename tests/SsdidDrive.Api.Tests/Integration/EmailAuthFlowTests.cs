using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests for all email-auth, TOTP, and OIDC endpoints.
/// These tests verify validation gates and error paths without requiring a
/// seeded database or real external services.
/// </summary>
public class EmailAuthFlowTests : IClassFixture<SsdidDriveFactory>
{
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public EmailAuthFlowTests(SsdidDriveFactory factory)
    {
        _client = factory.CreateClient();
    }

    // ── Task 5: Email Registration ──

    [Fact]
    public async Task Register_WithoutInvitation_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register",
            new { email = "test@example.com" }, SnakeJson);
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task Register_WithInvalidInvitation_Returns404()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register",
            new { email = "test@example.com", invitation_token = "invalid-token" }, SnakeJson);
        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task RegisterVerify_WithWrongCode_Returns404()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register/verify",
            new { email = "test@example.com", code = "000000", invitation_token = "invalid" }, SnakeJson);
        // No pending session for this email, so OTP lookup returns NotFound
        Assert.True(resp.StatusCode == HttpStatusCode.NotFound
            || resp.StatusCode == HttpStatusCode.Unauthorized);
    }

    // ── Task 6: TOTP Setup ──

    [Fact]
    public async Task TotpSetup_WithoutAuth_Returns401()
    {
        var resp = await _client.PostAsync("/api/auth/totp/setup", null);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task TotpSetupConfirm_WithoutAuth_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/totp/setup/confirm",
            new { code = "123456" }, SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    // ── Task 7: Email Login ──

    [Fact]
    public async Task EmailLogin_UnknownEmail_Returns200_AntiEnumeration()
    {
        // Anti-enumeration: unknown email returns same 200 as known email
        var resp = await _client.PostAsJsonAsync("/api/auth/email/login",
            new { email = "nonexistent@example.com" }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
        var json = await resp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        Assert.True(json.GetProperty("requires_totp").GetBoolean());
    }

    [Fact]
    public async Task EmailLogin_MissingEmail_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/login",
            new { email = "" }, SnakeJson);
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task TotpVerify_WrongCode_Returns401Or404()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/totp/verify",
            new { email = "test@example.com", code = "000000" }, SnakeJson);
        Assert.True(resp.StatusCode == HttpStatusCode.Unauthorized
            || resp.StatusCode == HttpStatusCode.NotFound);
    }

    // ── Task 8: OIDC Verify ──

    [Fact]
    public async Task OidcVerify_MissingProvider_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/oidc/verify",
            new { provider = "", id_token = "fake" }, SnakeJson);
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task OidcVerify_KnownProvider_NotConfigured_ReturnsErrorStatus()
    {
        // In the test environment OIDC client IDs are not set. The validator
        // returns ServiceUnavailable (503) or InternalServerError (500) depending
        // on rate limiter state and error handling.
        var resp = await _client.PostAsJsonAsync("/api/auth/oidc/verify",
            new { provider = "google", id_token = "not.a.valid.jwt" }, SnakeJson);
        Assert.True(
            resp.StatusCode == HttpStatusCode.ServiceUnavailable ||
            resp.StatusCode == HttpStatusCode.InternalServerError,
            $"Expected 503 or 500 but got {(int)resp.StatusCode}");
    }

    // ── Task 10: TOTP Recovery ──

    [Fact]
    public async Task TotpRecovery_UnknownEmail_Returns404()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/totp/recovery",
            new { email = "nonexistent@example.com" }, SnakeJson);
        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task TotpRecovery_MissingEmail_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/totp/recovery",
            new { email = "" }, SnakeJson);
        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task TotpRecoveryVerify_WrongCode_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/totp/recovery/verify",
            new { email = "test@example.com", code = "000000" }, SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    // ── Account endpoints (require auth) ──

    [Fact]
    public async Task ListLogins_WithoutAuth_Returns401()
    {
        var resp = await _client.GetAsync("/api/account/logins");
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task LinkEmail_WithoutAuth_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/account/logins/email",
            new { email = "new@example.com" }, SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task LinkEmailVerify_WithoutAuth_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/account/logins/email/verify",
            new { email = "test@example.com", code = "123456" }, SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task LinkOidc_WithoutAuth_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/account/logins/oidc",
            new { provider = "google", id_token = "fake" }, SnakeJson);
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }

    [Fact]
    public async Task UnlinkLogin_WithoutAuth_Returns401()
    {
        var resp = await _client.DeleteAsync($"/api/account/logins/{Guid.NewGuid()}");
        Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
    }
}
