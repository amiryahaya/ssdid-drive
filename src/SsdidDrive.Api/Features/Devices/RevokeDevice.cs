using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Devices;

public static class RevokeDevice
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == id, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        if (device.UserId != user.Id)
            return AppError.Forbidden("Only the device owner can revoke this device").ToProblemResult();

        device.Status = DeviceStatus.Revoked;
        device.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
