using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Files;

internal static class FileHelper
{
    internal static object BuildFileDto(FileItem f, Guid tenantId) => new
    {
        f.Id,
        f.FolderId,
        OwnerId = f.UploadedById,
        TenantId = tenantId,
        f.StoragePath,
        f.BlobSize,
        f.BlobHash,
        f.ChunkCount,
        f.Status,
        EncryptedMetadata = f.EncryptedMetadata ?? "",
        WrappedDek = f.WrappedDek ?? "",
        f.KemCiphertext,
        f.MlKemCiphertext,
        Signature = f.Signature ?? "",
        InsertedAt = f.CreatedAt,
        f.UpdatedAt,
        UploaderPublicKeys = (object?)null
    };
}
