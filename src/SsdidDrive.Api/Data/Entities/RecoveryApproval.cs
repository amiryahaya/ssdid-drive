namespace SsdidDrive.Api.Data.Entities;

public class RecoveryApproval
{
    public Guid Id { get; set; }
    public Guid RecoveryRequestId { get; set; }
    public Guid TrusteeId { get; set; }
    public byte[]? EncryptedShare { get; set; }
    public DateTimeOffset ApprovedAt { get; set; }

    public RecoveryRequest RecoveryRequest { get; set; } = null!;
    public User Trustee { get; set; } = null!;
}
