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

        var shares = await db.Shares
            .Where(s => s.SharedWithId == user.Id
                && (s.ExpiresAt == null || s.ExpiresAt > DateTimeOffset.UtcNow))
            .Include(s => s.SharedBy)
            .OrderByDescending(s => s.CreatedAt)
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
            .ToListAsync(ct);

        return Results.Ok(shares);
    }
}
