namespace SsdidDrive.Api.Data.Entities;

public class FileItem
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public long Size { get; set; }
    public string StoragePath { get; set; } = string.Empty;
    public Guid FolderId { get; set; }
    public Guid UploadedById { get; set; }

    // Legacy direct-encryption fields
    public byte[]? EncryptedFileKey { get; set; }
    public byte[]? Nonce { get; set; }
    public string? EncryptionAlgorithm { get; set; }

    // E2EE upload flow fields
    public string Status { get; set; } = "complete";
    public long? BlobSize { get; set; }
    public string? BlobHash { get; set; }
    public int ChunkCount { get; set; }
    public string? EncryptedMetadata { get; set; }
    public string? WrappedDek { get; set; }
    public string? KemCiphertext { get; set; }
    public string? MlKemCiphertext { get; set; }
    public string? Signature { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Folder Folder { get; set; } = null!;
    public User UploadedBy { get; set; } = null!;
}
