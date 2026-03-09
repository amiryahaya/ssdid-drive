using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Devices;

public static class ListDevices
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        [AsParameters] PaginationParams pagination,
        bool? include_revoked,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var query = db.Devices.Where(d => d.UserId == user.Id);

        if (include_revoked != true)
            query = query.Where(d => d.Status != DeviceStatus.Revoked);

        var total = await query.CountAsync(ct);

        // Order client-side for cross-database compatibility
        // (SQLite cannot ORDER BY DateTimeOffset columns).
        var devices = (await query.ToListAsync(ct))
            .OrderByDescending(d => d.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
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

        return Results.Ok(new PagedResponse<object>(devices, total, pagination.NormalizedPage, pagination.Take));
    }
}
