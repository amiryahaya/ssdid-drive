using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class SwitchTenant
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/me/switch-tenant/{tenantId:guid}", Handle);

    private static async Task<IResult> Handle(Guid tenantId, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var membership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == user.Id && ut.TenantId == tenantId, ct);

        if (membership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        user.TenantId = tenantId;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            active_tenant_id = tenantId,
            Role = membership.Role.ToString().ToLowerInvariant()
        });
    }
}
