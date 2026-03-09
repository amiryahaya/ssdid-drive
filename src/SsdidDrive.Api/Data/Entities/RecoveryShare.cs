namespace SsdidDrive.Api.Data.Entities;

public class RecoveryShare
{
    public Guid Id { get; set; }
    public Guid RecoveryConfigId { get; set; }
    public Guid TrusteeId { get; set; }
    public byte[] EncryptedShare { get; set; } = default!;
    public RecoveryShareStatus Status { get; set; } = RecoveryShareStatus.Pending;
    public DateTimeOffset CreatedAt { get; set; }

    public RecoveryConfig Config { get; set; } = null!;
    public User Trustee { get; set; } = null!;
}

public enum RecoveryShareStatus { Pending, Accepted, Rejected }
