using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Tenants;

public static class RemoveMember
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}/members/{userId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Guid userId,
        AppDbContext db, CurrentUserAccessor accessor, AuditService audit, CancellationToken ct)
    {
        var user = accessor.User!;

        if (userId == user.Id)
            return AppError.BadRequest("Cannot remove yourself. Use a leave endpoint instead").ToProblemResult();

        var callerMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == user.Id, ct);

        if (callerMembership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        if (callerMembership.Role == TenantRole.Member)
            return AppError.Forbidden("Only owners and admins can remove members").ToProblemResult();

        var targetMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == userId, ct);

        if (targetMembership is null)
            return AppError.NotFound("Member not found in this tenant").ToProblemResult();

        if (callerMembership.Role == TenantRole.Admin && targetMembership.Role == TenantRole.Owner)
            return AppError.Forbidden("Admins cannot remove owners").ToProblemResult();

        if (targetMembership.Role == TenantRole.Owner)
        {
            var ownerCount = await db.UserTenants
                .CountAsync(ut => ut.TenantId == id && ut.Role == TenantRole.Owner, ct);

            if (ownerCount <= 1)
                return AppError.BadRequest("Cannot remove the last owner of a tenant").ToProblemResult();
        }

        // Cascade-revoke pending invitations created by the removed member
        var revokedCount = await db.Invitations
            .Where(i => i.InvitedById == userId
                && i.TenantId == id
                && i.Status == InvitationStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Status, InvitationStatus.Revoked)
                .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

        db.UserTenants.Remove(targetMembership);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(user.Id, "tenant.member.removed", "UserTenant", null,
            $"Removed user {userId} from tenant {id} (role: {targetMembership.Role}). Revoked {revokedCount} pending invitation(s).", ct);

        return Results.NoContent();
    }
}
