namespace SsdidDrive.Api.Data.Entities;

public class Share
{
    public Guid Id { get; set; }
    public Guid ResourceId { get; set; }
    public string ResourceType { get; set; } = string.Empty; // "file" or "folder"
    public Guid SharedById { get; set; }
    public Guid SharedWithId { get; set; }
    public string Permission { get; set; } = "read";
    public byte[]? EncryptedKey { get; set; }
    public string? KemAlgorithm { get; set; }
    public DateTimeOffset? ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User SharedBy { get; set; } = null!;
    public User SharedWith { get; set; } = null!;
}
