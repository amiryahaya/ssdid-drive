namespace SsdidDrive.Api.Data.Entities;

public enum LoginProvider { Email, Google, Microsoft }

public class Login
{
    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public LoginProvider Provider { get; set; }
    public string ProviderSubject { get; set; } = default!;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset LinkedAt { get; set; }

    public User Account { get; set; } = null!;
}
