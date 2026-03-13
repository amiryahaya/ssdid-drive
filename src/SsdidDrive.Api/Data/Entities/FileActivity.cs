namespace SsdidDrive.Api.Data.Entities;

public static class FileActivityEventType
{
    public const string FileUploaded = "file_uploaded";
    public const string FileDownloaded = "file_downloaded";
    public const string FileRenamed = "file_renamed";
    public const string FileMoved = "file_moved";
    public const string FileDeleted = "file_deleted";
    public const string FilePreviewed = "file_previewed";
    public const string FileShared = "file_shared";
    public const string ShareRevoked = "share_revoked";
    public const string SharePermissionChanged = "share_permission_changed";
    public const string FolderCreated = "folder_created";
    public const string FolderRenamed = "folder_renamed";
    public const string FolderDeleted = "folder_deleted";
}

public class FileActivity
{
    public Guid Id { get; set; }
    public Guid ActorId { get; set; }
    public Guid TenantId { get; set; }
    public string EventType { get; set; } = string.Empty;
    public string ResourceType { get; set; } = string.Empty;
    public Guid ResourceId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public Guid ResourceOwnerId { get; set; }
    public string? Details { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User Actor { get; set; } = null!;
}
