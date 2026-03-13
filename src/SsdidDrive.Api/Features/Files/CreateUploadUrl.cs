using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Files;

public static class CreateUploadUrl
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/files/upload-url", Handle);

    private record Request(
        string FolderId,
        long BlobSize,
        string EncryptedMetadata,
        string WrappedDek,
        string? KemCiphertext,
        string? MlKemCiphertext,
        string Signature,
        int ChunkCount);

    private static async Task<IResult> Handle(
        Request request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        HttpContext httpContext,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        if (!Guid.TryParse(request.FolderId, out var folderId))
            return AppError.BadRequest("Invalid folder ID").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == folderId && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Check ownership or write share access
        var now = DateTimeOffset.UtcNow;
        if (folder.OwnerId != user.Id)
        {
            var hasWriteShare = (await db.Shares
                .Where(s => s.ResourceId == folderId && s.ResourceType == "folder"
                    && s.SharedWithId == user.Id && s.Permission == "write")
                .Select(s => new { s.ExpiresAt })
                .ToListAsync(ct))
                .Any(s => s.ExpiresAt == null || s.ExpiresAt > now);

            if (!hasWriteShare)
                return AppError.Forbidden("You do not have write access to this folder").ToProblemResult();
        }

        var fileId = Guid.NewGuid();
        var storagePath = Path.Combine(user.TenantId.Value.ToString(), folderId.ToString(), fileId.ToString());

        var fileItem = new FileItem
        {
            Id = fileId,
            Name = "encrypted",
            ContentType = "application/octet-stream",
            Size = request.BlobSize,
            StoragePath = storagePath,
            FolderId = folderId,
            UploadedById = user.Id,
            Status = "pending",
            BlobSize = request.BlobSize,
            ChunkCount = request.ChunkCount,
            EncryptedMetadata = request.EncryptedMetadata,
            WrappedDek = request.WrappedDek,
            KemCiphertext = request.KemCiphertext,
            MlKemCiphertext = request.MlKemCiphertext,
            Signature = request.Signature,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Files.Add(fileItem);
        await db.SaveChangesAsync(ct);

        var baseUrl = $"{httpContext.Request.Scheme}://{httpContext.Request.Host}";
        var uploadUrl = $"{baseUrl}/api/files/{fileId}/blob";

        return Results.Ok(new
        {
            Data = new
            {
                File = FileHelper.BuildFileDto(fileItem, folder.TenantId),
                UploadUrl = uploadUrl
            }
        });
    }
}
