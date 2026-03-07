namespace SsdidDrive.Api.Data.Entities;

public class Folder
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public Guid? ParentFolderId { get; set; }
    public Guid OwnerId { get; set; }
    public Guid TenantId { get; set; }
    public byte[]? EncryptedFolderKey { get; set; }
    public string? KemAlgorithm { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Folder? ParentFolder { get; set; }
    public User Owner { get; set; } = null!;
    public Tenant Tenant { get; set; } = null!;
    public ICollection<Folder> SubFolders { get; set; } = [];
    public ICollection<FileItem> Files { get; set; } = [];
}
