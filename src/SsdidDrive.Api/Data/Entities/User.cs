namespace SsdidDrive.Api.Data.Entities;

public enum UserStatus { Active, Suspended }

public class User
{
    public Guid Id { get; set; }
    public string? Did { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public UserStatus Status { get; set; } = UserStatus.Active;
    public SystemRole? SystemRole { get; set; }

    // Zero-knowledge key storage (client-side encrypted)
    public string? PublicKeys { get; set; } // JSON
    public byte[]? EncryptedPrivateKeys { get; set; }
    public byte[]? EncryptedMasterKey { get; set; }
    public byte[]? KeyDerivationSalt { get; set; }
    public byte[]? KemPublicKey { get; set; }
    public string? KemAlgorithm { get; set; }

    public DateTimeOffset? LastLoginAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public bool HasRecoverySetup { get; set; }

    // Auth: TOTP
    public string? TotpSecret { get; set; }
    public bool TotpEnabled { get; set; }
    public string? BackupCodes { get; set; } // Encrypted JSON array
    public bool EmailVerified { get; set; }

    // Linked logins
    public ICollection<Login> Logins { get; set; } = [];

    // TenantId is the user's default/primary tenant.
    // UserTenants is the full membership list (a user can belong to multiple tenants).
    public Guid? TenantId { get; set; }
    public Tenant? Tenant { get; set; }
    public ICollection<UserTenant> UserTenants { get; set; } = [];
}
