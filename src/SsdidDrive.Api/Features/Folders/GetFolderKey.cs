using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class GetFolderKey
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}/key", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Owner gets the folder's own encrypted key
        if (folder.OwnerId == user.Id)
        {
            return Results.Ok(new
            {
                EncryptedFolderKey = folder.EncryptedFolderKey is not null
                    ? Convert.ToBase64String(folder.EncryptedFolderKey)
                    : null,
                folder.KemAlgorithm,
                folder.FolderKeyVersion
            });
        }

        // Non-owner: check for a valid share
        var now = DateTimeOffset.UtcNow;
        var share = await db.Shares
            .Where(s => s.ResourceId == id)
            .Where(s => s.ResourceType == "folder")
            .Where(s => s.SharedWithId == user.Id)
            .FirstOrDefaultAsync(ct);

        // Filter expired shares in application code (SQLite compatibility)
        if (share is not null && share.ExpiresAt.HasValue && share.ExpiresAt <= now)
            share = null;

        if (share is null)
            return AppError.Forbidden("You do not have access to this folder's key").ToProblemResult();

        return Results.Ok(new
        {
            EncryptedFolderKey = share.EncryptedKey is not null
                ? Convert.ToBase64String(share.EncryptedKey)
                : null,
            share.KemAlgorithm,
            folder.FolderKeyVersion
        });
    }
}
