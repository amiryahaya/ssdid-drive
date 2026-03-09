using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
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

        // Only the invited user can accept
        var isInvitedUser = invitation.InvitedUserId == user.Id;

        if (!isInvitedUser)
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
