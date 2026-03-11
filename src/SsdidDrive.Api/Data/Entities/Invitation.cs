namespace SsdidDrive.Api.Data.Entities;

public class Invitation
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid InvitedById { get; set; }
    public string? Email { get; set; }                        // Invited email (may not have account yet)
    public Guid? InvitedUserId { get; set; }                  // Set if user already exists
    public TenantRole Role { get; set; } = TenantRole.Member;
    public InvitationStatus Status { get; set; } = InvitationStatus.Pending;
    public string Token { get; set; } = default!;             // Deep link token (URL-safe base64)
    public string ShortCode { get; set; } = default!;         // Human-readable code (e.g. ACME-7K9X)
    public string? Message { get; set; }                      // Optional invite message
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Tenant Tenant { get; set; } = null!;
    public User InvitedBy { get; set; } = null!;
    public User? InvitedUser { get; set; }
}

public enum InvitationStatus { Pending, Accepted, Declined, Expired, Revoked }
