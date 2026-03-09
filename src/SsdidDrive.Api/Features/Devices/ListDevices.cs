using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class ListDevices
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        // Order client-side for cross-database compatibility
        // (SQLite cannot ORDER BY DateTimeOffset columns).
        var devices = (await db.Devices
            .Where(d => d.UserId == user.Id)
            .ToListAsync(ct))
            .OrderByDescending(d => d.CreatedAt)
            .Select(d => new
            {
                d.Id,
                d.UserId,
                d.DeviceFingerprint,
                d.DeviceName,
                d.Platform,
                d.DeviceInfo,
                Status = d.Status.ToString().ToLowerInvariant(),
                d.KeyAlgorithm,
                PublicKey = d.PublicKey != null ? Convert.ToBase64String(d.PublicKey) : null,
                d.LastUsedAt,
                d.CreatedAt,
                d.UpdatedAt
            })
            .ToList();

        return Results.Ok(devices);
    }
}
