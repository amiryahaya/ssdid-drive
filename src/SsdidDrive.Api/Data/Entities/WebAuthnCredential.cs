namespace SsdidDrive.Api.Data.Entities;

public class WebAuthnCredential
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string CredentialId { get; set; } = default!;      // Base64url-encoded
    public byte[] PublicKey { get; set; } = default!;
    public string? Name { get; set; }                          // User-given name
    public long SignCount { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
