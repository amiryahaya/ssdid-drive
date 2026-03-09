using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class DeleteFile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/files/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, IStorageService storage, CancellationToken ct)
    {
        var user = accessor.User!;

        var file = await db.Files
            .Include(f => f.Folder)
            .FirstOrDefaultAsync(f => f.Id == id && f.Folder.TenantId == user.TenantId, ct);

        if (file is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (file.UploadedById != user.Id && file.Folder.OwnerId != user.Id)
            return AppError.Forbidden("Only the file uploader or folder owner can delete this file").ToProblemResult();

        // Delete any shares for this file
        var shares = await db.Shares
            .Where(s => s.ResourceId == id && s.ResourceType == "file")
            .ToListAsync(ct);
        db.Shares.RemoveRange(shares);

        var storagePath = file.StoragePath;
        db.Files.Remove(file);
        await db.SaveChangesAsync(ct);

        // Best-effort physical file deletion after DB commit
        await storage.DeleteAsync(storagePath, ct);

        return Results.NoContent();
    }
}
