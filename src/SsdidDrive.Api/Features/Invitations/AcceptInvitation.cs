using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, CancellationToken ct)
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
            return AppError.BadRequest("Invitation has expired").ToProblemResult();
        }

        // Authorization: if InvitedUserId is set, only that user can accept.
        // If InvitedUserId is null (user wasn't registered at invite time),
        // any authenticated user can accept — they proved token knowledge to get the invitation ID.
        if (invitation.InvitedUserId is not null && invitation.InvitedUserId != user.Id)
            return AppError.Forbidden("You are not the invited user").ToProblemResult();

        // Check if user is already in the tenant
        var existingMembership = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId, ct);

        if (existingMembership)
            return AppError.Conflict("You are already a member of this tenant").ToProblemResult();

        // Accept the invitation
        invitation.Status = InvitationStatus.Accepted;
        invitation.InvitedUserId = user.Id;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;

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

        return Results.Ok(new
        {
            invitation.Id,
            Status = invitation.Status.ToString().ToLowerInvariant(),
            invitation.TenantId,
            Role = invitation.Role.ToString().ToLowerInvariant()
        });
    }
}
