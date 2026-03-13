using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class DeleteRecoverySetup
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/setup", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        FileActivityService activity,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var setup = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id, ct);

        if (setup is null)
            return Results.NoContent();

        setup.IsActive = false;
        setup.ServerShare = "";
        user.HasRecoverySetup = false;
        await db.SaveChangesAsync(ct);

        _ = activity.LogAsync(
            user.Id, user.TenantId ?? Guid.Empty, "recovery.deactivated", "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.NoContent();
    }
}
