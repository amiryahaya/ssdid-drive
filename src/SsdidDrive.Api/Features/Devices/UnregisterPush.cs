using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class UnregisterPush
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{deviceId:guid}/push", Handle);

    private static async Task<IResult> Handle(
        Guid deviceId,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var device = await db.Devices
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == accessor.UserId, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        device.PushPlayerId = null;
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
