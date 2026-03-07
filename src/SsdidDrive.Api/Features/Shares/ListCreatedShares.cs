using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class ListCreatedShares
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/created", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Order client-side for cross-database compatibility
        // (SQLite cannot ORDER BY DateTimeOffset columns).
        var shares = (await db.Shares
            .Where(s => s.SharedById == user.Id)
            .Include(s => s.SharedWith)
            .Select(s => new
            {
                s.Id,
                s.ResourceId,
                s.ResourceType,
                s.SharedById,
                s.SharedWithId,
                SharedWithName = s.SharedWith.DisplayName ?? s.SharedWith.Did,
                s.Permission,
                s.KemAlgorithm,
                s.ExpiresAt,
                s.CreatedAt
            })
            .ToListAsync(ct))
            .OrderByDescending(s => s.CreatedAt)
            .ToList();

        return Results.Ok(shares);
    }
}
