using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class DownloadFile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/files/{id:guid}/download", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, IStorageService storage, FileActivityService activity, CancellationToken ct)
    {
        var user = accessor.User!;

        var file = await db.Files
            .Include(f => f.Folder)
            .FirstOrDefaultAsync(f => f.Id == id, ct);

        if (file is null)
            return AppError.NotFound("File not found").ToProblemResult();

        // Return 404 (not 403) for cross-tenant access to prevent file existence enumeration
        if (user.TenantId is null || file.Folder.TenantId != user.TenantId)
            return AppError.NotFound("File not found").ToProblemResult();

        // Check ownership or share access (file-level or folder-level).
        // Evaluate expiry client-side for cross-database compatibility
        // (SQLite cannot compare DateTimeOffset in LINQ).
        var now = DateTimeOffset.UtcNow;
        var hasAccess = file.UploadedById == user.Id
            || file.Folder.OwnerId == user.Id
            || (await db.Shares
                .Where(s => ((s.ResourceId == id && s.ResourceType == "file")
                    || (s.ResourceId == file.FolderId && s.ResourceType == "folder"))
                    && s.SharedWithId == user.Id && s.RevokedAt == null)
                .Select(s => s.ExpiresAt)
                .ToListAsync(ct))
                .Any(e => e == null || e > now);

        if (!hasAccess)
            return AppError.Forbidden("You do not have access to this file").ToProblemResult();

        var stream = await storage.RetrieveAsync(file.StoragePath, ct);

        _ = activity.LogAsync(user.Id, user.TenantId!.Value, FileActivityEventType.FileDownloaded,
            "file", file.Id, file.Name, file.UploadedById,
            new { size = file.Size, content_type = file.ContentType }, ct);

        return Results.File(stream, file.ContentType, file.Name);
    }
}
