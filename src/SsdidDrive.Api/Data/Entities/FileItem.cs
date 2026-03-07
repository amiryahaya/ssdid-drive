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
    public byte[]? EncryptedFileKey { get; set; }
    public byte[]? Nonce { get; set; }
    public string? EncryptionAlgorithm { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Folder Folder { get; set; } = null!;
    public User UploadedBy { get; set; } = null!;
}
