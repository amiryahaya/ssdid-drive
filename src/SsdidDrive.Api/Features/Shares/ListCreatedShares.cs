using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class ListCreatedShares
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/created", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor,
        int page = 1, int pageSize = 50,
        CancellationToken ct = default)
    {
        var user = accessor.User!;
        var pagination = new PaginationParams(page, pageSize);

        // Order client-side for cross-database compatibility
        // (SQLite cannot ORDER BY DateTimeOffset columns).
        var allShares = (await db.Shares
            .Where(s => s.SharedById == user.Id && s.RevokedAt == null)
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

        var total = allShares.Count;
        var items = allShares
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .ToList();

        return Results.Ok(new PagedResponse<object>(items, total, pagination.NormalizedPage, pagination.Take));
    }
}
