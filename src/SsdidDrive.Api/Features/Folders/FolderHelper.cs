using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Folders;

internal static class FolderHelper
{
    internal static object BuildFolderDto(Folder f) => new
    {
        f.Id,
        ParentId = f.ParentFolderId,
        f.OwnerId,
        f.TenantId,
        IsRoot = f.ParentFolderId is null,
        EncryptedMetadata = f.EncryptedMetadata,
        MetadataNonce = f.MetadataNonce,
        WrappedKek = f.WrappedKek ?? (f.EncryptedFolderKey is not null ? Convert.ToBase64String(f.EncryptedFolderKey) : ""),
        f.KemCiphertext,
        OwnerWrappedKek = f.OwnerWrappedKek ?? (f.EncryptedFolderKey is not null ? Convert.ToBase64String(f.EncryptedFolderKey) : ""),
        OwnerKemCiphertext = f.OwnerKemCiphertext ?? "",
        f.MlKemCiphertext,
        f.OwnerMlKemCiphertext,
        f.Signature,
        Owner = (object?)null,
        f.CreatedAt,
        f.UpdatedAt
    };
}
