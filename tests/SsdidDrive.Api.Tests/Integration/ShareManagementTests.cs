using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ShareManagementTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public ShareManagementTests(SsdidDriveFactory factory) => _factory = factory;

    // ── Helper: create a share and return the share id ──────────────────

    private async Task<(HttpClient ownerClient, HttpClient recipientClient, Guid recipientId, string shareId, string folderId)>
        SetupShareAsync(string ownerName, string recipientName, string permission = "read")
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, ownerName);
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, recipientName);

        var folderId = await TestFixture.CreateFolderAsync(client1, $"{ownerName} Folder");
        var (status, body) = await TestFixture.CreateShareAsync(client1, folderId, userId2, permission);
        Assert.Equal(HttpStatusCode.Created, status);

        var shareId = body.GetProperty("id").GetString()!;
        return (client1, client2, userId2, shareId, folderId);
    }

    // ── 1. GetShare as owner → 200 ─────────────────────────────────────

    [Fact]
    public async Task GetShare_AsOwner_Returns200()
    {
        var (ownerClient, _, _, shareId, folderId) = await SetupShareAsync("GetShareOwner", "GetShareRecip");

        var response = await ownerClient.GetAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(shareId, body.GetProperty("id").GetString());
        Assert.Equal(folderId, body.GetProperty("resource_id").GetString());
        Assert.Equal("folder", body.GetProperty("resource_type").GetString());
        Assert.Equal("read", body.GetProperty("permission").GetString());
    }

    // ── 2. GetShare as recipient → 200 ─────────────────────────────────

    [Fact]
    public async Task GetShare_AsRecipient_Returns200()
    {
        var (_, recipientClient, recipientId, shareId, _) = await SetupShareAsync("GetShareOwner2", "GetShareRecip2");

        var response = await recipientClient.GetAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(shareId, body.GetProperty("id").GetString());
        Assert.Equal(recipientId, body.GetProperty("shared_with_id").GetGuid());
    }

    // ── 3. GetShare as unrelated user → 404 ────────────────────────────

    [Fact]
    public async Task GetShare_AsUnrelatedUser_Returns404()
    {
        var (_, _, _, shareId, _) = await SetupShareAsync("GetShareOwner3", "GetShareRecip3");

        // Create a third unrelated user
        var (unrelatedClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "UnrelatedUser");

        var response = await unrelatedClient.GetAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 4. UpdatePermission as owner → 200 ─────────────────────────────

    [Fact]
    public async Task UpdatePermission_AsOwner_Returns200()
    {
        var (ownerClient, _, _, shareId, _) = await SetupShareAsync("PermOwner", "PermRecip", "read");

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/permission",
            new { permission = "write" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("write", body.GetProperty("permission").GetString());

        // Verify persistence via GET
        var getResp = await ownerClient.GetAsync($"/api/shares/{shareId}");
        var getBody = await getResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("write", getBody.GetProperty("permission").GetString());
    }

    // ── 5. UpdatePermission as recipient → 403 ─────────────────────────

    [Fact]
    public async Task UpdatePermission_AsRecipient_Returns403()
    {
        var (_, recipientClient, _, shareId, _) = await SetupShareAsync("PermOwner2", "PermRecip2");

        var response = await recipientClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/permission",
            new { permission = "write" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── 6. UpdatePermission with invalid value → 400 ───────────────────

    [Fact]
    public async Task UpdatePermission_InvalidValue_Returns400()
    {
        var (ownerClient, _, _, shareId, _) = await SetupShareAsync("PermOwner3", "PermRecip3");

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/permission",
            new { permission = "admin" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 7. SetExpiry as owner → 200 ────────────────────────────────────

    [Fact]
    public async Task SetExpiry_AsOwner_Returns200()
    {
        var (ownerClient, _, _, shareId, _) = await SetupShareAsync("ExpiryOwner", "ExpiryRecip");

        var futureDate = DateTimeOffset.UtcNow.AddDays(30);

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/expiry",
            new { expires_at = futureDate },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("expires_at", out var expiresAt));
        Assert.NotEqual(JsonValueKind.Null, expiresAt.ValueKind);
    }

    // ── 8. SetExpiry with past date → 400 ──────────────────────────────

    [Fact]
    public async Task SetExpiry_PastDate_Returns400()
    {
        var (ownerClient, _, _, shareId, _) = await SetupShareAsync("ExpiryOwner2", "ExpiryRecip2");

        var pastDate = DateTimeOffset.UtcNow.AddDays(-1);

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/expiry",
            new { expires_at = pastDate },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 9. SetExpiry with null (remove expiry) → 200 ───────────────────

    [Fact]
    public async Task SetExpiry_Null_RemovesExpiry_Returns200()
    {
        var (ownerClient, _, _, shareId, _) = await SetupShareAsync("ExpiryOwner3", "ExpiryRecip3");

        // First set an expiry
        var futureDate = DateTimeOffset.UtcNow.AddDays(30);
        await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/expiry",
            new { expires_at = futureDate },
            TestFixture.Json);

        // Then remove it
        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/shares/{shareId}/expiry",
            new { expires_at = (DateTimeOffset?)null },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(JsonValueKind.Null, body.GetProperty("expires_at").ValueKind);
    }
}
