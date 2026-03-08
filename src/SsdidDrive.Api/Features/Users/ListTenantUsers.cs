using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class ListTenantUsers
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/users", Handle);

    private static async Task<IResult> Handle(CurrentUserAccessor accessor, AppDbContext db)
    {
        var tenantId = accessor.User!.TenantId;
        if (tenantId is null) return Results.Ok(Array.Empty<object>());

        var users = await db.UserTenants
            .Where(ut => ut.TenantId == tenantId)
            .Select(ut => new { ut.User.Id, ut.User.Did, ut.User.DisplayName })
            .ToListAsync();

        return Results.Ok(users);
    }
}
