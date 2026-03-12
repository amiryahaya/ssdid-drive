using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminInvitationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public AdminInvitationTests(SsdidDriveFactory factory) => _factory = factory;

    private async Task<(HttpClient Client, Guid TenantId)> CreateAdminWithTenant(string name = "InvAdmin")
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, name, systemRole: "SuperAdmin");
        var slug = $"inv-{Guid.NewGuid():N}"[..20];
        var createResp = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "InviteTenant", slug }, TestFixture.Json);
        createResp.EnsureSuccessStatusCode();
        var tenant = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return (client, tenant.GetProperty("id").GetGuid());
    }

    [Fact]
    public async Task CreateInvitation_Owner_ReturnsCreated()
    {
        var (client, tenantId) = await CreateAdminWithTenant("OwnerInvAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "owner@test.com", role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("owner", body.GetProperty("role").GetString());
        Assert.Equal("owner@test.com", body.GetProperty("email").GetString());
        Assert.Equal("pending", body.GetProperty("status").GetString());
        Assert.True(body.TryGetProperty("short_code", out var code));
        Assert.False(string.IsNullOrEmpty(code.GetString()));
    }

    [Fact]
    public async Task CreateInvitation_Admin_ReturnsCreated()
    {
        var (client, tenantId) = await CreateAdminWithTenant("AdminInvAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "admin@test.com", role = "admin" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("admin", body.GetProperty("role").GetString());
    }

    [Fact]
    public async Task CreateInvitation_MemberRole_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("MemberRoleAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "member@test.com", role = "member" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_NonSuperAdmin_Returns403()
    {
        var (regularClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RegularInvUser");
        var response = await regularClient.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "test@test.com", role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_TenantNotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotFoundInvAdmin", systemRole: "SuperAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{Guid.NewGuid()}/invitations",
            new { email = "test@test.com", role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_MissingEmail_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("NoEmailAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_InvalidEmail_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("BadEmailAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "not-an-email", role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_DuplicatePending_Returns409()
    {
        var (client, tenantId) = await CreateAdminWithTenant("DupInvAdmin");
        var email = $"dup-{Guid.NewGuid():N}@test.com";
        var first = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email, role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var second = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email, role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_ExistingMember_Returns409()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExistMemberAdmin", systemRole: "SuperAdmin");
        var (_, targetUserId, targetTenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExistingMember");
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var user = await db.Users.FindAsync(targetUserId);
        user!.Email = "existing@test.com";
        await db.SaveChangesAsync();
        var response = await adminClient.PostAsJsonAsync(
            $"/api/admin/tenants/{targetTenantId}/invitations",
            new { email = "existing@test.com", role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task AcceptInvitation_OwnerRole_AddsUserAsOwner()
    {
        var (adminClient, tenantId) = await CreateAdminWithTenant("AcceptOwnerAdmin");
        var createResp = await adminClient.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "newowner@test.com", role = "owner" }, TestFixture.Json);
        createResp.EnsureSuccessStatusCode();
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = created.GetProperty("id").GetGuid();
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var invitation = await db.Invitations.FindAsync(invitationId);
        var invToken = invitation!.Token;
        var (acceptingClient, acceptingUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NewOwner");
        var acceptResp = await acceptingClient.PostAsJsonAsync(
            $"/api/invitations/{invitationId}/accept",
            new { token = invToken }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, acceptResp.StatusCode);
        var acceptBody = await acceptResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("owner", acceptBody.GetProperty("role").GetString());
        using var scope2 = _factory.Services.CreateScope();
        var db2 = scope2.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var membership = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions.FirstOrDefaultAsync(
            db2.UserTenants.Where(ut => ut.UserId == acceptingUserId && ut.TenantId == tenantId));
        Assert.NotNull(membership);
        Assert.Equal(SsdidDrive.Api.Data.Entities.TenantRole.Owner, membership.Role);
    }
}
