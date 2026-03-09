using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Tenants;

public static class RemoveMember
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}/members/{userId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Guid userId,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Cannot remove self
        if (userId == user.Id)
            return AppError.BadRequest("Cannot remove yourself. Use a leave endpoint instead").ToProblemResult();

        // Check caller is Admin or Owner
        var callerMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == user.Id, ct);

        if (callerMembership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        if (callerMembership.Role == TenantRole.Member)
            return AppError.Forbidden("Only owners and admins can remove members").ToProblemResult();

        // Find target membership
        var targetMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == userId, ct);

        if (targetMembership is null)
            return AppError.NotFound("Member not found in this tenant").ToProblemResult();

        // Admin cannot remove Owner
        if (callerMembership.Role == TenantRole.Admin && targetMembership.Role == TenantRole.Owner)
            return AppError.Forbidden("Admins cannot remove owners").ToProblemResult();

        // Cannot remove the last owner
        if (targetMembership.Role == TenantRole.Owner)
        {
            var ownerCount = await db.UserTenants
                .CountAsync(ut => ut.TenantId == id && ut.Role == TenantRole.Owner, ct);

            if (ownerCount <= 1)
                return AppError.BadRequest("Cannot remove the last owner of a tenant").ToProblemResult();
        }

        db.UserTenants.Remove(targetMembership);
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
