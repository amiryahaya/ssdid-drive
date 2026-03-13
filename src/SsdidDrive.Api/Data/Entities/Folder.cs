namespace SsdidDrive.Api.Data.Entities;

public class Folder
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public Guid? ParentFolderId { get; set; }
    public Guid OwnerId { get; set; }
    public Guid TenantId { get; set; }

    // Legacy field (kept for backward compat)
    public byte[]? EncryptedFolderKey { get; set; }
    public string? KemAlgorithm { get; set; }
    public int FolderKeyVersion { get; set; } = 1;

    // E2EE fields
    public string? EncryptedMetadata { get; set; }
    public string? MetadataNonce { get; set; }
    public string? WrappedKek { get; set; }
    public string? KemCiphertext { get; set; }
    public string? OwnerWrappedKek { get; set; }
    public string? OwnerKemCiphertext { get; set; }
    public string? MlKemCiphertext { get; set; }
    public string? OwnerMlKemCiphertext { get; set; }
    public string? Signature { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Folder? ParentFolder { get; set; }
    public User Owner { get; set; } = null!;
    public Tenant Tenant { get; set; } = null!;
    public ICollection<Folder> SubFolders { get; set; } = [];
    public ICollection<FileItem> Files { get; set; } = [];
}
