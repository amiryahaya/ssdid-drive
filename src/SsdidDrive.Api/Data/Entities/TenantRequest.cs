namespace SsdidDrive.Api.Data.Entities;

public enum TenantRequestStatus { Pending, Approved, Rejected }

public class TenantRequest
{
    public Guid Id { get; set; }
    public string OrganizationName { get; set; } = default!;
    public string RequesterEmail { get; set; } = default!;
    public Guid? RequesterAccountId { get; set; }
    public string? Reason { get; set; }
    public TenantRequestStatus Status { get; set; } = TenantRequestStatus.Pending;
    public Guid? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public string? RejectionReason { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User? RequesterAccount { get; set; }
    public User? Reviewer { get; set; }
}
