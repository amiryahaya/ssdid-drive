using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class ListReceivedShares
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/received", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Fetch shares for the current user, then filter expired client-side
        // (SQLite cannot compare DateTimeOffset in LINQ).
        var now = DateTimeOffset.UtcNow;
        // Order client-side for cross-database compatibility
        // (SQLite cannot ORDER BY DateTimeOffset columns).
        var shares = (await db.Shares
            .Where(s => s.SharedWithId == user.Id)
            .Include(s => s.SharedBy)
            .Select(s => new
            {
                s.Id,
                s.ResourceId,
                s.ResourceType,
                s.SharedById,
                SharedByName = s.SharedBy.DisplayName ?? s.SharedBy.Did,
                s.SharedWithId,
                s.Permission,
                EncryptedKey = s.EncryptedKey != null ? Convert.ToBase64String(s.EncryptedKey) : null,
                s.KemAlgorithm,
                s.ExpiresAt,
                s.CreatedAt
            })
            .ToListAsync(ct))
            .Where(s => s.ExpiresAt == null || s.ExpiresAt > now)
            .OrderByDescending(s => s.CreatedAt)
            .ToList();

        return Results.Ok(shares);
    }
}
