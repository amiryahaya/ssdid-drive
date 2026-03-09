using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Shares;

public static class RevokeShare
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, CancellationToken ct)
    {
        var user = accessor.User!;

        var share = await db.Shares.FirstOrDefaultAsync(s => s.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Share not found").ToProblemResult();

        if (share.SharedById != user.Id)
            return AppError.Forbidden("Only the original sharer can revoke a share").ToProblemResult();

        var recipientId = share.SharedWithId;
        db.Shares.Remove(share);

        await notifications.CreateAsync(
            recipientId,
            "share_revoked",
            "Share Revoked",
            "A share has been revoked",
            actionType: "share",
            actionResourceId: id.ToString(),
            ct: ct);

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
