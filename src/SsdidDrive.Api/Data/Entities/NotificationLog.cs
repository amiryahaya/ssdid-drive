namespace SsdidDrive.Api.Data.Entities;

public class NotificationLog
{
    public Guid Id { get; set; }
    public Guid? SentById { get; set; }
    public string Scope { get; set; } = string.Empty;  // "user", "tenant", "broadcast"
    public Guid? TargetId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public int RecipientCount { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User SentBy { get; set; } = null!;
}
