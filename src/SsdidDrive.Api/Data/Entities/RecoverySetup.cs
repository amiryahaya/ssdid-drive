namespace SsdidDrive.Api.Data.Entities;

public class RecoverySetup
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string ServerShare { get; set; } = default!;
    public string KeyProof { get; set; } = default!;
    public DateTimeOffset ShareCreatedAt { get; set; }
    public bool IsActive { get; set; }
    public int Threshold { get; set; }

    public User User { get; set; } = null!;
    public ICollection<RecoveryTrustee> Trustees { get; set; } = [];
}
