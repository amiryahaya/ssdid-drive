namespace SsdidDrive.Api.Data.Entities;

public class Notification
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Type { get; set; } = default!;              // "share_received", "share_revoked", "invitation_received", etc.
    public string Title { get; set; } = default!;
    public string Message { get; set; } = default!;
    public bool IsRead { get; set; }
    public string? ActionType { get; set; }                   // "open_share", "open_file", "open_invitation", etc.
    public string? ActionResourceId { get; set; }             // ID of related resource
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
