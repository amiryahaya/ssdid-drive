using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class UpdateDevice
{
    public record Request(string? DeviceName);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == id, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        if (device.UserId != user.Id)
            return AppError.Forbidden("Only the device owner can update this device").ToProblemResult();

        device.DeviceName = req.DeviceName;
        device.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

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
