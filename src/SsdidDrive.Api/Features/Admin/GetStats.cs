using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class GetStats
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/stats", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CancellationToken ct)
    {
        var userCount = await db.Users.CountAsync(ct);
        var tenantCount = await db.Tenants.CountAsync(ct);
        var fileCount = await db.Files.CountAsync(ct);
        var totalStorageBytes = await db.Files.SumAsync(f => f.Size, ct);

        return Results.Ok(new
        {
            user_count = userCount,
            tenant_count = tenantCount,
            file_count = fileCount,
            total_storage_bytes = totalStorageBytes,
            active_session_count = 0
        });
    }
}
