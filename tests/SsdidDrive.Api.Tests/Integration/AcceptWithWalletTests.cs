using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AcceptWithWalletTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public AcceptWithWalletTests(SsdidDriveFactory factory) => _factory = factory;

    // ── 1. Happy path: valid credential + matching email → 200 with session ──

    [Fact]
    public async Task AcceptWithWallet_ValidCredential_MatchingEmail_Returns200()
    {
        // Arrange: create tenant + owner + invitation
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner1");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "wallet-user@example.com");

        // Create a wallet identity and register it
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // Act: accept with wallet (anonymous client, no auth header)
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "wallet-user@example.com" },
            TestFixture.Json);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(string.IsNullOrEmpty(body.GetProperty("session_token").GetString()));
        Assert.Equal(walletIdentity.Did, body.GetProperty("did").GetString());
        Assert.True(body.TryGetProperty("user", out var user));
        Assert.True(body.TryGetProperty("tenant", out var tenant));
        Assert.Equal("member", tenant.GetProperty("role").GetString());
    }

    // ── 2. Email mismatch → 403 ──

    [Fact]
    public async Task AcceptWithWallet_EmailMismatch_Returns403()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner2");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "correct@example.com");

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "wrong@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── 3. Expired invitation → 404 ──

    [Fact]
    public async Task AcceptWithWallet_ExpiredToken_Returns404()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner3");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "expired@example.com",
            expiresAt: DateTimeOffset.UtcNow.AddDays(-1));

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "expired@example.com" },
            TestFixture.Json);

        // Expired invitations now return 410 Gone
        Assert.Equal(HttpStatusCode.Gone, response.StatusCode);
    }

    // ── 4. Already accepted → second attempt returns 409 ──

    [Fact]
    public async Task AcceptWithWallet_AlreadyAccepted_Returns409()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner4");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "double@example.com");

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var client = _factory.CreateClient();

        // First accept
        var first = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "double@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        // Second accept
        var second = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "double@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    // ── 5. Creates new user + UserTenant, sets AcceptedByDid/AcceptedAt ──

    [Fact]
    public async Task AcceptWithWallet_CreatesNewUser_WhenDidNotInDb()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner5");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "newuser@example.com");

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential, email = "newuser@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify user was created in DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var user = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.Users, u => u.Did == walletIdentity.Did);
        Assert.NotNull(user);
        Assert.Null(user.DisplayName); // wallet-created users have no display name initially

        // Verify UserTenant
        var userTenant = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.UserTenants, ut => ut.UserId == user.Id && ut.TenantId == tenantId);
        Assert.NotNull(userTenant);
        Assert.Equal(TenantRole.Member, userTenant.Role);

        // Verify AcceptedByDid and AcceptedAt on invitation
        var invitation = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstAsync(db.Invitations, i => i.Token == invitationToken);
        Assert.Equal(walletIdentity.Did, invitation.AcceptedByDid);
        Assert.NotNull(invitation.AcceptedAt);
        Assert.Equal(InvitationStatus.Accepted, invitation.Status);
    }

    // ── 6. Invalid credential → 401 ──

    [Fact]
    public async Task AcceptWithWallet_InvalidCredential_Returns401()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletOwner6");
        var invitationToken = await CreatePendingInvitation(_factory, tenantId, ownerId, "invalid@example.com");

        // Use garbage credential
        var garbageCredential = JsonSerializer.SerializeToElement(new
        {
            context = new[] { "https://www.w3.org/2018/credentials/v1" },
            id = "urn:uuid:fake",
            type = new[] { "VerifiableCredential" },
            issuer = "did:ssdid:fake",
            credentialSubject = new { id = "did:ssdid:fake" }
        });

        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync(
            $"/api/invitations/token/{invitationToken}/accept-with-wallet",
            new { credential = garbageCredential, email = "invalid@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── Helper: insert a pending invitation directly ──

    private static async Task<string> CreatePendingInvitation(
        SsdidDriveFactory factory, Guid tenantId, Guid invitedById, string email,
        DateTimeOffset? expiresAt = null)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var token = Convert.ToBase64String(Guid.NewGuid().ToByteArray())
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');

        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            InvitedById = invitedById,
            Email = email,
            Role = TenantRole.Member,
            Status = InvitationStatus.Pending,
            Token = token,
            ShortCode = $"TST-{Guid.NewGuid():N}"[..8].ToUpper(),
            ExpiresAt = expiresAt ?? DateTimeOffset.UtcNow.AddDays(7),
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Invitations.Add(invitation);
        await db.SaveChangesAsync();

        return token;
    }
}
