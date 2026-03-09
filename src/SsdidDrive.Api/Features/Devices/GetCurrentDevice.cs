using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class GetCurrentDevice
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/current", Handle);

    private static async Task<IResult> Handle(string fingerprint, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var device = await db.Devices
            .FirstOrDefaultAsync(d => d.UserId == user.Id && d.DeviceFingerprint == fingerprint, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        return Results.Ok(new
        {
            device.Id,
            device.UserId,
            device.DeviceFingerprint,
            device.DeviceName,
            device.Platform,
            device.DeviceInfo,
            Status = device.Status.ToString(),
            device.KeyAlgorithm,
            PublicKey = device.PublicKey is not null ? Convert.ToBase64String(device.PublicKey) : null,
            device.LastUsedAt,
            device.CreatedAt,
            device.UpdatedAt
        });
    }
}
