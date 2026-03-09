using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Tenants;

public static class ListMembers
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}/members", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Check caller is a member of this tenant
        var callerMembership = await db.UserTenants
            .AnyAsync(ut => ut.TenantId == id && ut.UserId == user.Id, ct);

        if (!callerMembership)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        var memberships = await db.UserTenants
            .Where(ut => ut.TenantId == id)
            .Include(ut => ut.User)
            .ToListAsync(ct);

        var members = memberships.OrderBy(ut => ut.CreatedAt).Select(ut => new
        {
            ut.UserId,
            ut.User.Did,
            DisplayName = ut.User.DisplayName,
            Role = ut.Role.ToString().ToLowerInvariant(),
            ut.CreatedAt
        }).ToList();

        return Results.Ok(members);
    }
}
