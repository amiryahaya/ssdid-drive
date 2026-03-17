namespace SsdidDrive.Api.Data.Entities;

public class Device
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string DeviceFingerprint { get; set; } = default!;
    public string? DeviceName { get; set; }
    public string Platform { get; set; } = default!;         // "android", "ios", "macos", "windows", "linux"
    public string? DeviceInfo { get; set; }                   // JSON (model, OS version, app version)
    public DeviceStatus Status { get; set; } = DeviceStatus.Active;
    public string KeyAlgorithm { get; set; } = default!;     // "kaz_sign", "ml_dsa"
    public byte[]? PublicKey { get; set; }                    // Device signing public key
    public string? PushPlayerId { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}

public enum DeviceStatus { Active, Suspended, Revoked }
