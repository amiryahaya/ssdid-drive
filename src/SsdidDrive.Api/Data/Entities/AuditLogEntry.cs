namespace SsdidDrive.Api.Data.Entities;

public class AuditLogEntry
{
    public Guid Id { get; set; }
    public Guid ActorId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string? TargetType { get; set; }
    public Guid? TargetId { get; set; }
    public string? Details { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User Actor { get; set; } = null!;
}
