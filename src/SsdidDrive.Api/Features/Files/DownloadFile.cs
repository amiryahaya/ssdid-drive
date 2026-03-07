using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class DownloadFile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/files/{id:guid}/download", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, IStorageService storage, CancellationToken ct)
    {
        var user = accessor.User!;

        var file = await db.Files
            .Include(f => f.Folder)
            .FirstOrDefaultAsync(f => f.Id == id, ct);

        if (file is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (user.TenantId is null || file.Folder.TenantId != user.TenantId)
            return AppError.Forbidden("You do not have access to this file").ToProblemResult();

        // Check ownership or share access (file-level or folder-level)
        var hasAccess = file.UploadedById == user.Id
            || file.Folder.OwnerId == user.Id
            || await db.Shares.AnyAsync(s =>
                ((s.ResourceId == id && s.ResourceType == "file")
                 || (s.ResourceId == file.FolderId && s.ResourceType == "folder"))
                && s.SharedWithId == user.Id
                && (s.ExpiresAt == null || s.ExpiresAt > DateTimeOffset.UtcNow), ct);

        if (!hasAccess)
            return AppError.Forbidden("You do not have access to this file").ToProblemResult();

        var stream = await storage.RetrieveAsync(file.StoragePath, ct);
        return Results.File(stream, file.ContentType, file.Name);
    }
}
