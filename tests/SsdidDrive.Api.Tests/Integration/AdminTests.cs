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
    public async Task AdminSessions_ReturnsSessionCounts()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SessionAdmin", systemRole: "SuperAdmin");
        var response = await client.GetAsync("/api/admin/sessions");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("active_sessions", out _));
        Assert.True(body.TryGetProperty("active_challenges", out _));
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

    [Fact]
    public async Task AdminCreateTenant_CreatesAndLists()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantAdmin", systemRole: "SuperAdmin");
        var slug = "testcorp-" + Guid.NewGuid().ToString("N")[..8];

        var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "TestCorp", slug }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);

        var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("TestCorp", created.GetProperty("name").GetString());
        Assert.Equal(slug, created.GetProperty("slug").GetString());

        var listResponse = await client.GetAsync("/api/admin/tenants");
        Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);

        var body = await listResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var items));
        Assert.True(items.GetArrayLength() >= 1);
    }

    [Fact]
    public async Task AdminUpdateTenant_DisablesTenant()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DisableAdmin", systemRole: "SuperAdmin");
        var slug = "disable-" + Guid.NewGuid().ToString("N")[..8];

        var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "ToDisable", slug }, TestFixture.Json);
        var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var tenantId = created.GetProperty("id").GetGuid();

        var patchResponse = await client.PatchAsJsonAsync($"/api/admin/tenants/{tenantId}",
            new { disabled = true }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, patchResponse.StatusCode);

        var body = await patchResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.GetProperty("disabled").GetBoolean());
    }

    [Fact]
    public async Task AdminCreateTenant_DuplicateSlug_ReturnsConflict()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DupAdmin", systemRole: "SuperAdmin");
        var slug = "dup-" + Guid.NewGuid().ToString("N")[..8];

        await client.PostAsJsonAsync("/api/admin/tenants", new { name = "First", slug }, TestFixture.Json);
        var response = await client.PostAsJsonAsync("/api/admin/tenants", new { name = "Second", slug }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task AdminCreateTenant_MissingName_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NoNameAdmin", systemRole: "SuperAdmin");
        var response = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "", slug = "valid-slug" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task AdminGetTenantMembers_NotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "MemberAdmin", systemRole: "SuperAdmin");
        var response = await client.GetAsync($"/api/admin/tenants/{Guid.NewGuid()}/members");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AdminGetTenantMembers_ReturnsMembers()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "MemberListAdmin", systemRole: "SuperAdmin");
        var slug = "members-" + Guid.NewGuid().ToString("N")[..8];

        var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "MembersCorp", slug }, TestFixture.Json);
        var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var tenantId = created.GetProperty("id").GetGuid();

        var response = await client.GetAsync($"/api/admin/tenants/{tenantId}/members");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var members));
        Assert.Equal(JsonValueKind.Array, members.ValueKind);
    }

    [Fact]
    public async Task AdminUpdateTenant_NotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantNotFoundAdmin", systemRole: "SuperAdmin");
        var response = await client.PatchAsJsonAsync($"/api/admin/tenants/{Guid.NewGuid()}",
            new { name = "Updated" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AdminAuditLog_RecordsUserSuspension()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditTarget");

        await client.PatchAsJsonAsync($"/api/admin/users/{targetId}",
            new { status = "suspended" }, TestFixture.Json);

        var response = await client.GetAsync("/api/admin/audit-log");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);

        // Check first entry has expected fields
        var entry = items[0];
        Assert.True(entry.TryGetProperty("action", out _));
        Assert.True(entry.TryGetProperty("actor_id", out _));
        Assert.True(entry.TryGetProperty("created_at", out _));
    }

    [Fact]
    public async Task AdminAuditLog_RecordsTenantDisable()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditTenantAdmin", systemRole: "SuperAdmin");
        var slug = "audit-" + Guid.NewGuid().ToString("N")[..8];

        var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "AuditCorp", slug }, TestFixture.Json);
        var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var tenantId = created.GetProperty("id").GetGuid();

        await client.PatchAsJsonAsync($"/api/admin/tenants/{tenantId}",
            new { disabled = true }, TestFixture.Json);

        var response = await client.GetAsync("/api/admin/audit-log");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);

        // Find the tenant.disabled entry
        var found = false;
        foreach (var entry in items.EnumerateArray())
        {
            if (entry.GetProperty("action").GetString() == "tenant.disabled")
            {
                found = true;
                Assert.Equal(tenantId, entry.GetProperty("target_id").GetGuid());
                break;
            }
        }
        Assert.True(found, "Expected a tenant.disabled audit entry");
    }

    [Fact]
    public async Task AdminListTenants_SearchFilters()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantSearchAdmin", systemRole: "SuperAdmin");
        var uniqueName = "UniqueSearch-" + Guid.NewGuid().ToString("N")[..8];
        var slug = "search-" + Guid.NewGuid().ToString("N")[..8];

        await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = uniqueName, slug }, TestFixture.Json);

        var response = await client.GetAsync($"/api/admin/tenants?search={uniqueName}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);
    }
}
