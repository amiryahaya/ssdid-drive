namespace SsdidDrive.Api.Data.Entities;

public class ExtensionService
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Name { get; set; } = default!;
    public string ServiceKey { get; set; } = default!; // Encrypted HMAC secret
    public string Permissions { get; set; } = "{}"; // JSON permissions object
    public bool Enabled { get; set; } = true;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }

    public Tenant Tenant { get; set; } = null!;
}
