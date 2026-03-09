using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Admin;

public static class AdminFeature
{
    public static void MapAdminFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/admin")
            .WithTags("Admin")
            .AddEndpointFilter(async (ctx, next) =>
            {
                var accessor = ctx.HttpContext.RequestServices.GetRequiredService<CurrentUserAccessor>();
                if (accessor.SystemRole != SystemRole.SuperAdmin)
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "System administrator access required");
                return await next(ctx);
            });

        GetStats.Map(group);
    }
}
