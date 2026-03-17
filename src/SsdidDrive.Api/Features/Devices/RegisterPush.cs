using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class RegisterPush
{
    public record Request(string PlayerId);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{deviceId:guid}/push", Handle);

    private static async Task<IResult> Handle(
        Guid deviceId, Request req,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var device = await db.Devices
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == accessor.UserId, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.PlayerId))
            return AppError.BadRequest("player_id is required").ToProblemResult();

        device.PushPlayerId = req.PlayerId.Trim();
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
