namespace SsdidDrive.Api.Data.Entities;

public class RecoveryTrustee
{
    public Guid Id { get; set; }
    public Guid RecoverySetupId { get; set; }
    public Guid TrusteeUserId { get; set; }
    public byte[] EncryptedShare { get; set; } = default!;
    public int ShareIndex { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public RecoverySetup RecoverySetup { get; set; } = null!;
    public User TrusteeUser { get; set; } = null!;
}
