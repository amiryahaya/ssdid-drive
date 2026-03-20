namespace SsdidDrive.Api.Data.Entities;

public enum ApprovalDecision { Approved, Rejected }

public class RecoveryRequestApproval
{
    public Guid Id { get; set; }
    public Guid RecoveryRequestId { get; set; }
    public Guid TrusteeUserId { get; set; }
    public ApprovalDecision Decision { get; set; }
    public DateTimeOffset DecidedAt { get; set; }

    public RecoveryRequest RecoveryRequest { get; set; } = null!;
    public User TrusteeUser { get; set; } = null!;
}
