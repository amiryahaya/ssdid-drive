using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class RenameFolder
{
    public record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length > 512)
            return AppError.BadRequest("Folder name is required (max 512 chars)").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != accessor.User!.Id)
            return AppError.Forbidden("Only the folder owner can rename it").ToProblemResult();

        folder.Name = req.Name.Trim();
        folder.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

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
