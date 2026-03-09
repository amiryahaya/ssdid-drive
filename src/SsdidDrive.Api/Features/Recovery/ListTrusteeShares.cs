using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Recovery;

public static class ListTrusteeShares
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/shares", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var shares = await db.RecoveryShares
            .Include(rs => rs.Config).ThenInclude(c => c.User)
            .Where(rs => rs.TrusteeId == user.Id)
            .ToListAsync(ct);

        shares = shares.OrderByDescending(rs => rs.CreatedAt).ToList();

        var items = shares.Select(rs => new
        {
            rs.Id,
            rs.RecoveryConfigId,
            rs.TrusteeId,
            EncryptedShare = Convert.ToBase64String(rs.EncryptedShare),
            Status = rs.Status.ToString(),
            rs.CreatedAt,
            ConfigOwnerDisplayName = rs.Config.User.DisplayName
        });

        return Results.Ok(new { Items = items });
    }
}
