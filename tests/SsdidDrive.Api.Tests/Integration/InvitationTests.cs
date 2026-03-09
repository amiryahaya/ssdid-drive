using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class InvitationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public InvitationTests(SsdidDriveFactory factory) => _factory = factory;

    // ── 1. CreateInvitation_AsOwner_ReturnsCreated ──────────────────────

    [Fact]
    public async Task CreateInvitation_AsOwner_ReturnsCreated()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvOwner");

        var response = await client.PostAsJsonAsync("/api/invitations", new
        {
            email = "invitee@example.com",
            role = "member",
            message = "Welcome!"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("invitee@example.com", body.GetProperty("email").GetString());
        Assert.Equal("member", body.GetProperty("role").GetString());
        Assert.Equal("Welcome!", body.GetProperty("message").GetString());
        Assert.Equal("pending", body.GetProperty("status").GetString());
        Assert.False(string.IsNullOrEmpty(body.GetProperty("token").GetString()));
        Assert.Equal(userId, body.GetProperty("invited_by_id").GetGuid());
    }

    // ── 2. CreateInvitation_AsMember_Returns403 ────────────────────────

    [Fact]
    public async Task CreateInvitation_AsMember_Returns403()
    {
        var (_, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvMemberOwner");
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "InvMember");

        var response = await memberClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "someone@example.com",
            role = "member"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── 3. ListReceivedInvitations_Returns200 ──────────────────────────

    [Fact]
    public async Task ListReceivedInvitations_Returns200()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvListOwner");
        var (memberClient, memberId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "InvListMember");

        // Create invitation targeting the member user by ID
        await CreateInvitationForUser(_factory, tenantId, ownerClient, memberId);

        var response = await memberClient.GetAsync("/api/invitations");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var invitations = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(invitations.GetArrayLength() >= 1);
    }

    // ── 4. ListSentInvitations_Returns200 ──────────────────────────────

    [Fact]
    public async Task ListSentInvitations_Returns200()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvSentOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "sent-target@example.com",
            role = "member"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);

        var response = await ownerClient.GetAsync("/api/invitations/sent");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var invitations = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(invitations.GetArrayLength() >= 1);
    }

    // ── 5. GetInvitationByToken_Valid_Returns200 ───────────────────────

    [Fact]
    public async Task GetInvitationByToken_Valid_Returns200()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvTokenOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "token-lookup@example.com",
            role = "member"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        // Use an unauthenticated client
        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync($"/api/invitations/token/{token}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("token-lookup@example.com", body.GetProperty("email").GetString());
    }

    // ── 6. GetInvitationByToken_Invalid_Returns404 ─────────────────────

    [Fact]
    public async Task GetInvitationByToken_Invalid_Returns404()
    {
        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync("/api/invitations/token/bogus-token-abc123");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 7. AcceptInvitation_Returns200_CreatesUserTenant ────────────────

    [Fact]
    public async Task AcceptInvitation_Returns200_CreatesUserTenant()
    {
        // Owner of tenant1 creates invitation
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvAcceptOwner");

        // Create a second tenant's user who will accept
        var (acceptClient, acceptUserId, acceptTenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvAcceptee");

        // Create invitation targeting the acceptee by user ID
        var invitationId = await CreateInvitationForUser(_factory, tenantId, ownerClient, acceptUserId);

        // Accept
        var response = await acceptClient.PostAsync($"/api/invitations/{invitationId}/accept", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify UserTenant was created
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var userTenant = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.UserTenants, ut => ut.UserId == acceptUserId && ut.TenantId == tenantId);
        Assert.NotNull(userTenant);
        Assert.Equal(TenantRole.Member, userTenant.Role);
    }

    // ── 8. DeclineInvitation_Returns200 ────────────────────────────────

    [Fact]
    public async Task DeclineInvitation_Returns200()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvDeclineOwner");
        var (declineClient, declineUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvDeclinee");

        var invitationId = await CreateInvitationForUser(_factory, tenantId, ownerClient, declineUserId);

        var response = await declineClient.PostAsync($"/api/invitations/{invitationId}/decline", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 9. RevokeInvitation_AsCreator_Returns204 ───────────────────────

    [Fact]
    public async Task RevokeInvitation_AsCreator_Returns204()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvRevokeOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "revoke-target@example.com",
            role = "member"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = createBody.GetProperty("id").GetString()!;

        var response = await ownerClient.DeleteAsync($"/api/invitations/{invitationId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    // ── 10. RevokeInvitation_AsNonCreator_Returns403 ───────────────────

    [Fact]
    public async Task RevokeInvitation_AsNonCreator_Returns403()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InvRevokeOwner2");
        var (otherClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "InvRevokeOther");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "revoke-target2@example.com",
            role = "member"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = createBody.GetProperty("id").GetString()!;

        // Another user tries to revoke
        var response = await otherClient.DeleteAsync($"/api/invitations/{invitationId}");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── Helper: Create invitation targeting a specific user ────────────

    private static async Task<string> CreateInvitationForUser(
        SsdidDriveFactory factory, Guid tenantId, HttpClient ownerClient, Guid targetUserId)
    {
        // Directly insert an invitation targeting a specific user ID
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Get the owner user for InvitedById
        var ownerUser = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstAsync(db.Users, u => u.TenantId == tenantId);

        // Also get the owner's UserTenant to confirm they're an owner
        var ownerUt = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstAsync(db.UserTenants, ut => ut.UserId == ownerUser.Id && ut.TenantId == tenantId);

        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            InvitedById = ownerUser.Id,
            InvitedUserId = targetUserId,
            Role = TenantRole.Member,
            Status = InvitationStatus.Pending,
            Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Invitations.Add(invitation);
        await db.SaveChangesAsync();

        return invitation.Id.ToString();
    }
}
