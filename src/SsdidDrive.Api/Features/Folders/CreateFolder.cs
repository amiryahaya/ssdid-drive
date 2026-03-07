using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Folders;

public static class CreateFolder
{
    public record Request(string Name, Guid? ParentFolderId, string EncryptedFolderKey, string KemAlgorithm);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length > 512)
            return AppError.BadRequest("Folder name is required (max 512 chars)").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.EncryptedFolderKey))
            return AppError.BadRequest("Encrypted folder key is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.KemAlgorithm))
            return AppError.BadRequest("KEM algorithm is required").ToProblemResult();

        if (req.ParentFolderId is not null)
        {
            var parent = await db.Folders
                .FirstOrDefaultAsync(f => f.Id == req.ParentFolderId && f.TenantId == user.TenantId, ct);
            if (parent is null)
                return AppError.NotFound("Parent folder not found").ToProblemResult();
        }

        var folder = new Folder
        {
            Name = req.Name.Trim(),
            ParentFolderId = req.ParentFolderId,
            OwnerId = user.Id,
            TenantId = user.TenantId.Value,
            EncryptedFolderKey = Convert.FromBase64String(req.EncryptedFolderKey),
            KemAlgorithm = req.KemAlgorithm,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Folders.Add(folder);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/folders/{folder.Id}", new
        {
            folder.Id,
            folder.Name,
            folder.ParentFolderId,
            folder.OwnerId,
            folder.TenantId,
            EncryptedFolderKey = Convert.ToBase64String(folder.EncryptedFolderKey!),
            folder.KemAlgorithm,
            folder.CreatedAt,
            folder.UpdatedAt
        });
    }
}
