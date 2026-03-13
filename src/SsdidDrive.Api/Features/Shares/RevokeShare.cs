using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Shares;

public static class RevokeShare
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, FileActivityService activity, CancellationToken ct)
    {
        var user = accessor.User!;

        var share = await db.Shares.FirstOrDefaultAsync(s => s.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Share not found").ToProblemResult();

        if (share.SharedById != user.Id)
            return AppError.Forbidden("Only the original sharer can revoke a share").ToProblemResult();

        var recipientId = share.SharedWithId;
        var shareResourceId = share.ResourceId;
        var shareResourceType = share.ResourceType;

        var resourceName = shareResourceType == "folder"
            ? (await db.Folders.Where(f => f.Id == shareResourceId).Select(f => f.Name).FirstOrDefaultAsync(ct) ?? "unknown")
            : (await db.Files.Where(f => f.Id == shareResourceId).Select(f => f.Name).FirstOrDefaultAsync(ct) ?? "unknown");

        var resourceOwnerId = shareResourceType == "folder"
            ? await db.Folders.Where(f => f.Id == shareResourceId).Select(f => f.OwnerId).FirstOrDefaultAsync(ct)
            : await db.Files.Where(f => f.Id == shareResourceId).Select(f => f.UploadedById).FirstOrDefaultAsync(ct);

        var recipient = await db.Users.FirstOrDefaultAsync(u => u.Id == recipientId, ct);
        var revokedFromName = recipient?.DisplayName ?? recipient?.Did ?? "unknown";

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

        _ = activity.LogAsync(user.Id, user.TenantId!.Value, FileActivityEventType.ShareRevoked,
            shareResourceType, shareResourceId, resourceName, resourceOwnerId,
            new { revoked_from_id = recipientId, revoked_from_name = revokedFromName }, ct);

        return Results.NoContent();
    }
}
