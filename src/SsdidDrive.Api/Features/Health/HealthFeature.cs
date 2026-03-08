using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Health;

public static class HealthFeature
{
    public static void MapHealthFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/health").WithTags("Health")
            .WithMetadata(new SsdidPublicAttribute());

        group.MapGet("/", () => Results.Ok(new { status = "ok" }));

        group.MapGet("/ready", async (AppDbContext db) =>
        {
            try
            {
                await db.Database.ExecuteSqlRawAsync("SELECT 1");
                return Results.Ok(new { status = "ready", database = "ok" });
            }
            catch
            {
                return Results.Problem(
                    statusCode: 503,
                    title: "Service Unavailable",
                    detail: "Database is not ready");
            }
        });
    }
}
