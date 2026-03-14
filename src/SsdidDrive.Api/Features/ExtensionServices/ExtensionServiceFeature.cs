using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class ExtensionServiceFeature
{
    public static void MapExtensionServiceFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/tenant/services")
            .WithTags("Extension Services")
            .AddEndpointFilter(async (ctx, next) =>
            {
                var accessor = ctx.HttpContext.RequestServices.GetRequiredService<CurrentUserAccessor>();
                var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();

                if (accessor.User?.TenantId is null)
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "No active tenant");

                var userTenant = await db.UserTenants
                    .FirstOrDefaultAsync(ut => ut.UserId == accessor.UserId && ut.TenantId == accessor.User.TenantId);

                if (userTenant is null || (userTenant.Role != TenantRole.Owner && userTenant.Role != TenantRole.Admin))
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "Owner or Admin role required");

                return await next(ctx);
            });

        RegisterService.Map(group);
        ListServices.Map(group);
        GetService.Map(group);
        UpdateService.Map(group);
        RevokeService.Map(group);
        RotateSecret.Map(group);
    }
}
