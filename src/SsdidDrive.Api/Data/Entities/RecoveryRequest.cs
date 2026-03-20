namespace SsdidDrive.Api.Data.Entities;

public enum RecoveryRequestStatus { Pending, Approved, Rejected, Expired, Completed }

public class RecoveryRequest
{
    public Guid Id { get; set; }
    public Guid RequesterId { get; set; }
    public Guid RecoverySetupId { get; set; }
    public RecoveryRequestStatus Status { get; set; } = RecoveryRequestStatus.Pending;
    public int ApprovedCount { get; set; }
    public int RequiredCount { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User Requester { get; set; } = null!;
    public RecoverySetup RecoverySetup { get; set; } = null!;
    public ICollection<RecoveryRequestApproval> Approvals { get; set; } = [];
}
