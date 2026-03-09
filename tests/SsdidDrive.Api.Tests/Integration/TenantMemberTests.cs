using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class TenantMemberTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public TenantMemberTests(SsdidDriveFactory factory) => _factory = factory;

    // ── ListMembers ─────────────────────────────────────────────────────

    [Fact]
    public async Task ListMembers_AsMember_Returns200WithMembers()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner1");
        var (memberClient, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member1");

        var response = await memberClient.GetAsync($"/api/tenants/{tenantId}/members");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var members = body.EnumerateArray().ToList();
        Assert.Equal(2, members.Count);

        var ownerEntry = members.First(m => m.GetProperty("user_id").GetGuid() == ownerId);
        Assert.Equal("owner", ownerEntry.GetProperty("role").GetString());
        Assert.Equal("TM-Owner1", ownerEntry.GetProperty("display_name").GetString());

        var memberEntry = members.First(m => m.GetProperty("user_id").GetGuid() == memberId);
        Assert.Equal("member", memberEntry.GetProperty("role").GetString());
    }

    [Fact]
    public async Task ListMembers_AsNonMember_Returns403()
    {
        var (_, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner2");
        var (outsiderClient, _) = await TestFixture.CreateUserInTenantAsync(
            _factory, (await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-OtherOwner")).TenantId, "TM-Outsider");

        var response = await outsiderClient.GetAsync($"/api/tenants/{tenantId}/members");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── UpdateMemberRole ────────────────────────────────────────────────

    [Fact]
    public async Task UpdateRole_AsOwner_Returns200()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner3");
        var (_, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member3");

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/tenants/{tenantId}/members/{memberId}",
            new { role = "admin" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("admin", body.GetProperty("role").GetString());
    }

    [Fact]
    public async Task UpdateRole_AsMember_Returns403()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner4");
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member4");

        var response = await memberClient.PatchAsJsonAsync(
            $"/api/tenants/{tenantId}/members/{ownerId}",
            new { role = "admin" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task UpdateRole_InvalidRole_Returns400()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner5");
        var (_, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member5");

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/tenants/{tenantId}/members/{memberId}",
            new { role = "superadmin" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task UpdateRole_DemoteLastOwner_Returns400()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner6");

        var response = await ownerClient.PatchAsJsonAsync(
            $"/api/tenants/{tenantId}/members/{ownerId}",
            new { role = "member" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── RemoveMember ────────────────────────────────────────────────────

    [Fact]
    public async Task RemoveMember_AsOwner_Returns204()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner7");
        var (_, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member7");

        var response = await ownerClient.DeleteAsync($"/api/tenants/{tenantId}/members/{memberId}");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // verify member is gone
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var exists = db.UserTenants.Any(ut => ut.UserId == memberId && ut.TenantId == tenantId);
        Assert.False(exists);
    }

    [Fact]
    public async Task RemoveMember_Self_Returns400()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner8");

        var response = await ownerClient.DeleteAsync($"/api/tenants/{tenantId}/members/{ownerId}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task RemoveMember_LastOwner_Returns400()
    {
        // Create tenant with an owner, then add admin. Try to remove the sole owner.
        var (adminClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner9");
        var (_, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Admin9");

        // promote member to admin
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var ut = db.UserTenants.Single(ut => ut.UserId == memberId && ut.TenantId == tenantId);
            ut.Role = TenantRole.Admin;
            await db.SaveChangesAsync();
        }

        // admin tries to remove the last owner — should fail because admin can't remove owner
        var (adminClient2, _) = await CreateAdminClient(tenantId);

        var response = await adminClient2.DeleteAsync($"/api/tenants/{tenantId}/members/{(await GetOwnerId(tenantId))}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RemoveMember_AsMember_Returns403()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-Owner10");
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member10");
        var (_, otherMemberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-Member10b");

        var response = await memberClient.DeleteAsync($"/api/tenants/{tenantId}/members/{otherMemberId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── helpers ──────────────────────────────────────────────────────────

    private async Task<(HttpClient Client, Guid UserId)> CreateAdminClient(Guid tenantId)
    {
        var (client, userId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-AdminHelper");

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var ut = db.UserTenants.Single(ut => ut.UserId == userId && ut.TenantId == tenantId);
        ut.Role = TenantRole.Admin;
        await db.SaveChangesAsync();

        return (client, userId);
    }

    private async Task<Guid> GetOwnerId(Guid tenantId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return db.UserTenants
            .Where(ut => ut.TenantId == tenantId && ut.Role == TenantRole.Owner)
            .Select(ut => ut.UserId)
            .First();
    }
}
