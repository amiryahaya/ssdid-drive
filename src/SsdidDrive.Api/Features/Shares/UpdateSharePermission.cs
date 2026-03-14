using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Shares;

public static class UpdateSharePermission
{
    public record Request(string Permission);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}/permission", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, FileActivityService activity, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var share = await db.Shares.FirstOrDefaultAsync(s => s.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Share not found").ToProblemResult();

        if (share.SharedById != user.Id)
            return AppError.Forbidden("Only the share owner can update permission").ToProblemResult();

        if (req.Permission is not ("read" or "write"))
            return AppError.BadRequest("Permission must be 'read' or 'write'").ToProblemResult();

        var oldPermission = share.Permission;
        share.Permission = req.Permission;
        await db.SaveChangesAsync(ct);

        var resourceName = share.ResourceType == "folder"
            ? (await db.Folders.Where(f => f.Id == share.ResourceId).Select(f => f.Name).FirstOrDefaultAsync(ct) ?? "unknown")
            : (await db.Files.Where(f => f.Id == share.ResourceId).Select(f => f.Name).FirstOrDefaultAsync(ct) ?? "unknown");

        var resourceOwnerId = share.ResourceType == "folder"
            ? await db.Folders.Where(f => f.Id == share.ResourceId).Select(f => f.OwnerId).FirstOrDefaultAsync(ct)
            : await db.Files.Where(f => f.Id == share.ResourceId).Select(f => f.UploadedById).FirstOrDefaultAsync(ct);

        var sharedWithUser = await db.Users.FirstOrDefaultAsync(u => u.Id == share.SharedWithId, ct);
        var userName = sharedWithUser?.DisplayName ?? sharedWithUser?.Did ?? "unknown";

        _ = activity.LogAsync(user.Id, user.TenantId.Value, FileActivityEventType.SharePermissionChanged,
            share.ResourceType, share.ResourceId, resourceName, resourceOwnerId,
            new { user_name = userName, old_permission = oldPermission, new_permission = req.Permission }, ct);

        return Results.Ok(new
        {
            share.Id,
            share.ResourceId,
            share.ResourceType,
            share.SharedById,
            share.SharedWithId,
            share.Permission,
            share.ExpiresAt,
            share.CreatedAt
        });
    }
}
