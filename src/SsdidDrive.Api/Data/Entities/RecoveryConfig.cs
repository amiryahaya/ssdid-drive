namespace SsdidDrive.Api.Data.Entities;

public class RecoveryConfig
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public int Threshold { get; set; }
    public int TotalShares { get; set; }
    public bool IsActive { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<RecoveryShare> Shares { get; set; } = [];
}
