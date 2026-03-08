namespace SsdidDrive.Api.Data.Entities;

public enum TenantRole { Member, Admin, Owner }

public class UserTenant
{
    public Guid UserId { get; set; }
    public User User { get; set; } = default!;

    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = default!;

    public TenantRole Role { get; set; } = TenantRole.Member;
    public DateTimeOffset CreatedAt { get; set; }
}
