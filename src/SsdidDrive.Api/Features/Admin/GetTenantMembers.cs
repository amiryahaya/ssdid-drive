using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class GetTenantMembers
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenants/{tenantId:guid}/members", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId,
        AppDbContext db,
        CancellationToken ct)
    {
        var tenantExists = await db.Tenants.AnyAsync(t => t.Id == tenantId, ct);
        if (!tenantExists)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        var members = await db.UserTenants
            .Where(ut => ut.TenantId == tenantId)
            .Include(ut => ut.User)
            .OrderBy(ut => ut.User.DisplayName)
            .Select(ut => new
            {
                user_id = ut.UserId,
                did = ut.User.Did,
                display_name = ut.User.DisplayName,
                email = ut.User.Email,
                role = ut.Role.ToString().ToLower(),
                joined_at = ut.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new { items = members });
    }
}
