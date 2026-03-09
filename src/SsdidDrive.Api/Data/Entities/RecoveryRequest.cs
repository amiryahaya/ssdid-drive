namespace SsdidDrive.Api.Data.Entities;

public class RecoveryRequest
{
    public Guid Id { get; set; }
    public Guid RequesterId { get; set; }
    public Guid RecoveryConfigId { get; set; }
    public RecoveryRequestStatus Status { get; set; } = RecoveryRequestStatus.Pending;
    public int ApprovalsReceived { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    /// <summary>Comma-separated GUIDs of trustees who have approved this request.</summary>
    public string? ApprovedBy { get; set; }

    public User Requester { get; set; } = null!;
    public RecoveryConfig Config { get; set; } = null!;
}

public enum RecoveryRequestStatus { Pending, Approved, Completed, Rejected, Expired }
