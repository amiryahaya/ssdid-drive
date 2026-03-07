using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Folders;

public static class DeleteFolder
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, IStorageService storage, CancellationToken ct)
    {
        var user = accessor.User!;

        var folder = await db.Folders
            .Include(f => f.Files)
            .Include(f => f.SubFolders)
            .FirstOrDefaultAsync(f => f.Id == id, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != user.Id)
            return AppError.Forbidden("Only the folder owner can delete it").ToProblemResult();

        // Recursively collect all descendant folders and their files
        await DeleteFolderRecursive(folder.Id, db, storage, ct);

        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task DeleteFolderRecursive(Guid folderId, AppDbContext db, IStorageService storage, CancellationToken ct)
    {
        var childFolders = await db.Folders
            .Where(f => f.ParentFolderId == folderId)
            .Select(f => f.Id)
            .ToListAsync(ct);

        foreach (var childId in childFolders)
            await DeleteFolderRecursive(childId, db, storage, ct);

        // Delete files on disk
        var files = await db.Files.Where(f => f.FolderId == folderId).ToListAsync(ct);
        foreach (var file in files)
            await storage.DeleteAsync(file.StoragePath, ct);

        // Delete shares for this folder
        var shares = await db.Shares
            .Where(s => s.ResourceId == folderId && s.ResourceType == "folder")
            .ToListAsync(ct);
        db.Shares.RemoveRange(shares);

        // Delete files and folder from DB
        db.Files.RemoveRange(files);

        var folder = await db.Folders.FindAsync([folderId], ct);
        if (folder is not null)
            db.Folders.Remove(folder);
    }
}
