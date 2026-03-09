using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Tenants;

public static class UpdateMemberRole
{
    public record UpdateRoleRequest(string Role);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}/members/{userId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Guid userId, UpdateRoleRequest request,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Validate role string
        if (!Enum.TryParse<TenantRole>(request.Role, ignoreCase: true, out var newRole))
            return AppError.BadRequest($"Invalid role '{request.Role}'. Valid roles: owner, admin, member").ToProblemResult();

        // Check caller is Owner of this tenant
        var callerMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == user.Id, ct);

        if (callerMembership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        if (callerMembership.Role != TenantRole.Owner)
            return AppError.Forbidden("Only owners can change member roles").ToProblemResult();

        // Find target membership
        var targetMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == userId, ct);

        if (targetMembership is null)
            return AppError.NotFound("Member not found in this tenant").ToProblemResult();

        // Prevent demoting the last owner
        if (targetMembership.Role == TenantRole.Owner && newRole != TenantRole.Owner)
        {
            var ownerCount = await db.UserTenants
                .CountAsync(ut => ut.TenantId == id && ut.Role == TenantRole.Owner, ct);

            if (ownerCount <= 1)
                return AppError.BadRequest("Cannot demote the last owner of a tenant").ToProblemResult();
        }

        targetMembership.Role = newRole;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            targetMembership.UserId,
            Role = targetMembership.Role.ToString().ToLowerInvariant(),
            targetMembership.TenantId
        });
    }
}
