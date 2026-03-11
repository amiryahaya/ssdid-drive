using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptInvitation
{
    public record Request(string? Token = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id && i.Status == InvitationStatus.Pending, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        // Check expiry
        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            invitation.Status = InvitationStatus.Expired;
            invitation.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return AppError.Gone("Invitation has expired").ToProblemResult();
        }

        // Authorization: if InvitedUserId is set, only that user can accept.
        if (invitation.InvitedUserId is not null && invitation.InvitedUserId != user.Id)
            return AppError.Forbidden("You are not the invited user").ToProblemResult();

        // For open invitations (InvitedUserId is null), require token proof
        if (invitation.InvitedUserId is null)
        {
            if (string.IsNullOrWhiteSpace(req.Token) ||
                !CryptographicOperations.FixedTimeEquals(
                    Encoding.UTF8.GetBytes(req.Token),
                    Encoding.UTF8.GetBytes(invitation.Token)))
                return AppError.Forbidden("Invalid or missing invitation token").ToProblemResult();
        }

        // Check if user is already in the tenant
        var existingMembership = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId, ct);

        if (existingMembership)
            return AppError.Conflict("You are already a member of this tenant").ToProblemResult();

        // Accept the invitation within a transaction to prevent TOCTOU races
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Atomically claim the invitation (WHERE Status = Pending prevents double-accept)
        var updated = await db.Invitations
            .Where(i => i.Id == id && i.Status == InvitationStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Status, InvitationStatus.Accepted)
                .SetProperty(i => i.InvitedUserId, user.Id)
                .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

        if (updated == 0)
            return AppError.Conflict("Invitation has already been processed").ToProblemResult();

        // Create UserTenant
        var userTenant = new UserTenant
        {
            UserId = user.Id,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.UserTenants.Add(userTenant);

        await notifications.CreateAsync(
            invitation.InvitedById,
            "invitation_accepted",
            "Invitation Accepted",
            $"{user.DisplayName ?? user.Did} accepted your invitation",
            actionType: "invitation",
            actionResourceId: invitation.Id.ToString(),
            ct: ct);

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return Results.Ok(new
        {
            Id = id,
            Status = "accepted",
            invitation.TenantId,
            Role = invitation.Role.ToString().ToLowerInvariant()
        });
    }
}
