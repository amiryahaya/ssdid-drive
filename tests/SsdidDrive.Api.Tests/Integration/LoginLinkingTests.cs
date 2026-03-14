using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests for account login linking endpoints.
///
/// Auth-gate tests (no session) verify that all account endpoints are
/// protected by SsdidAuthMiddleware. Full happy-path tests for link/unlink
/// flows are covered in the e2e suite once test helpers for session seeding
/// are available.
/// </summary>
public class LoginLinkingTests : IClassFixture<SsdidDriveFactory>
{
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public LoginLinkingTests(SsdidDriveFactory factory)
    {
        _client = factory.CreateClient();
    }

    // ── Auth gate: all /api/account/logins/* require a valid Bearer token ──

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
