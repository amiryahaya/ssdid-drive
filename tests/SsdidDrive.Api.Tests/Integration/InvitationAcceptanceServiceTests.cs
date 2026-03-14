using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class InvitationAcceptanceServiceTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public InvitationAcceptanceServiceTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AcceptInvitation_SuspendedUser_Returns403()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspOwner");
        var (suspendedClient, suspendedUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspUser");

        // Suspend the user
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var user = await db.Users.FindAsync(suspendedUserId);
            user!.Status = UserStatus.Suspended;
            await db.SaveChangesAsync();
        }

        // Create invitation targeting the suspended user
        Guid invitationId;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var invitation = new Invitation
            {
                Id = Guid.NewGuid(),
                TenantId = tenantId,
                InvitedById = ownerId,
                InvitedUserId = suspendedUserId,
                Role = TenantRole.Member,
                Status = InvitationStatus.Pending,
                Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
                ShortCode = "SUSP-TEST",
                ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };
            db.Invitations.Add(invitation);
            await db.SaveChangesAsync();
            invitationId = invitation.Id;
        }

        // Act
        var response = await suspendedClient.PostAsync($"/api/invitations/{invitationId}/accept", null);

        // Assert
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
