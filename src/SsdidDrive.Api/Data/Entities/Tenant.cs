namespace SsdidDrive.Api.Data.Entities;

public class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = default!;
    public string Slug { get; set; } = default!;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    public ICollection<User> Users { get; set; } = [];
    public ICollection<UserTenant> UserTenants { get; set; } = [];
}
