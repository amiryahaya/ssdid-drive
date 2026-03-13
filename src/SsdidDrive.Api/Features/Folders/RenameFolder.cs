using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Folders;

public static class RenameFolder
{
    public record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, FileActivityService activity, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length > 512)
            return AppError.BadRequest("Folder name is required (max 512 chars)").ToProblemResult();

        var user = accessor.User!;
        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != user.Id)
            return AppError.Forbidden("Only the folder owner can rename it").ToProblemResult();

        var oldName = folder.Name;
        folder.Name = req.Name.Trim();
        folder.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        _ = activity.LogAsync(user.Id, user.TenantId!.Value, FileActivityEventType.FolderRenamed,
            "folder", folder.Id, folder.Name, folder.OwnerId,
            new { old_name = oldName, new_name = folder.Name }, ct);

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
            folder.UpdatedAt
        });
    }
}
