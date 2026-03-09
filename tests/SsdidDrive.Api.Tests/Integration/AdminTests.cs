using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public AdminTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AdminStats_NonAdmin_Returns403()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RegularUser");
        var response = await client.GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task AdminStats_SuperAdmin_ReturnsStats()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminUser", systemRole: "SuperAdmin");
        var response = await client.GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("user_count", out _));
        Assert.True(body.TryGetProperty("tenant_count", out _));
        Assert.True(body.TryGetProperty("file_count", out _));
        Assert.True(body.TryGetProperty("total_storage_bytes", out _));
        Assert.True(body.TryGetProperty("active_session_count", out _));
    }

    [Fact]
    public async Task AdminListUsers_ReturnsAllUsers()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminLister", systemRole: "SuperAdmin");
        var response = await client.GetAsync("/api/admin/users");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var items));
        Assert.True(items.GetArrayLength() >= 1);
        Assert.True(body.TryGetProperty("total", out _));
    }

    [Fact]
    public async Task AdminListUsers_SearchFilters()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SearchAdmin", systemRole: "SuperAdmin");
        await TestFixture.CreateAuthenticatedClientAsync(_factory, "UniqueSearchTarget123");

        var response = await client.GetAsync("/api/admin/users?search=UniqueSearchTarget123");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);
        foreach (var item in items.EnumerateArray())
        {
            Assert.Contains("UniqueSearchTarget123", item.GetProperty("display_name").GetString());
        }
    }

    [Fact]
    public async Task AdminSuspendUser_ChangesStatus()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspendAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TargetUser");

        var response = await adminClient.PatchAsJsonAsync($"/api/admin/users/{targetId}",
            new { status = "suspended" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("suspended", body.GetProperty("status").GetString());
    }

    [Fact]
    public async Task AdminSuspendSelf_Returns400()
    {
        var (client, adminId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SelfSuspend", systemRole: "SuperAdmin");
        var response = await client.PatchAsJsonAsync($"/api/admin/users/{adminId}",
            new { status = "suspended" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AdminUpdateUser_InvalidStatus_Returns400()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "StatusAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "StatusTarget");

        var response = await adminClient.PatchAsJsonAsync($"/api/admin/users/{targetId}",
            new { status = "invalid" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AdminUpdateUser_NotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotFoundAdmin", systemRole: "SuperAdmin");
        var response = await client.PatchAsJsonAsync($"/api/admin/users/{Guid.NewGuid()}",
            new { status = "suspended" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AdminUpdateUser_SetSystemRole()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RoleAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RoleTarget");

        var response = await adminClient.PatchAsJsonAsync($"/api/admin/users/{targetId}",
            new { system_role = "SuperAdmin" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("SuperAdmin", body.GetProperty("system_role").GetString());
    }
}
