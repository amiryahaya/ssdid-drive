using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class UploadFile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/folders/{folderId:guid}/files", Handle).DisableAntiforgery();

    private static async Task<IResult> Handle(
        Guid folderId,
        IFormFile file,
        [FromForm] string encrypted_file_key,
        [FromForm] string nonce,
        [FromForm] string encryption_algorithm,
        AppDbContext db,
        CurrentUserAccessor accessor,
        IStorageService storage,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == folderId && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Check ownership or share access with write permission
        var now = DateTimeOffset.UtcNow;
        var hasWriteShare = false;
        if (folder.OwnerId != user.Id)
        {
            // Materialize first, then filter expiry client-side (InMemory/SQLite compatibility)
            hasWriteShare = (await db.Shares
                .Where(s => s.ResourceId == folderId && s.ResourceType == "folder"
                    && s.SharedWithId == user.Id && s.Permission == "write")
                .Select(s => new { s.ExpiresAt })
                .ToListAsync(ct))
                .Any(s => s.ExpiresAt == null || s.ExpiresAt > now);
        }
        var hasAccess = folder.OwnerId == user.Id || hasWriteShare;

        if (!hasAccess)
            return AppError.Forbidden("You do not have write access to this folder").ToProblemResult();

        if (file.Length == 0)
            return AppError.BadRequest("File is empty").ToProblemResult();

        if (string.IsNullOrWhiteSpace(encrypted_file_key))
            return AppError.BadRequest("Encrypted file key is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(nonce))
            return AppError.BadRequest("Nonce is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(encryption_algorithm))
            return AppError.BadRequest("Encryption algorithm is required").ToProblemResult();

        var fileId = Guid.NewGuid();

        await using var stream = file.OpenReadStream();
        var storagePath = await storage.StoreAsync(user.TenantId.Value, folderId, fileId, stream, ct);

        var fileItem = new FileItem
        {
            Id = fileId,
            Name = file.FileName,
            ContentType = file.ContentType ?? "application/octet-stream",
            Size = file.Length,
            StoragePath = storagePath,
            FolderId = folderId,
            UploadedById = user.Id,
            EncryptedFileKey = Convert.FromBase64String(encrypted_file_key),
            Nonce = Convert.FromBase64String(nonce),
            EncryptionAlgorithm = encryption_algorithm,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Files.Add(fileItem);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/files/{fileItem.Id}", new
        {
            fileItem.Id,
            fileItem.Name,
            fileItem.ContentType,
            fileItem.Size,
            fileItem.FolderId,
            fileItem.UploadedById,
            EncryptedFileKey = Convert.ToBase64String(fileItem.EncryptedFileKey!),
            Nonce = Convert.ToBase64String(fileItem.Nonce!),
            fileItem.EncryptionAlgorithm,
            fileItem.CreatedAt,
            fileItem.UpdatedAt
        });
    }
}
