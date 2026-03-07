using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class GetFolder
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var folder = await db.Folders
            .Where(f => f.Id == id && f.TenantId == user.TenantId)
            .Select(f => new
            {
                f.Id,
                f.Name,
                f.ParentFolderId,
                f.OwnerId,
                f.TenantId,
                f.EncryptedFolderKey,
                f.KemAlgorithm,
                f.CreatedAt,
                f.UpdatedAt,
                SubFolderCount = f.SubFolders.Count,
                FileCount = f.Files.Count
            })
            .FirstOrDefaultAsync(ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Check ownership or share access.
        // Evaluate expiry client-side for cross-database compatibility
        // (SQLite cannot compare DateTimeOffset in LINQ).
        var now = DateTimeOffset.UtcNow;
        var hasAccess = folder.OwnerId == user.Id
            || (await db.Shares
                .Where(s => s.ResourceId == id && s.ResourceType == "folder" && s.SharedWithId == user.Id)
                .Select(s => s.ExpiresAt)
                .ToListAsync(ct))
                .Any(e => e == null || e > now);

        if (!hasAccess)
            return AppError.Forbidden("You do not have access to this folder").ToProblemResult();

        return Results.Ok(new
        {
            folder.Id,
            folder.Name,
            folder.ParentFolderId,
            folder.OwnerId,
            folder.TenantId,
            EncryptedFolderKey = folder.EncryptedFolderKey is not null
                ? Convert.ToBase64String(folder.EncryptedFolderKey)
                : null,
            folder.KemAlgorithm,
            folder.CreatedAt,
            folder.UpdatedAt,
            folder.SubFolderCount,
            folder.FileCount
        });
    }
}
