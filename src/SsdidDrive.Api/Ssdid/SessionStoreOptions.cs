namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Configuration for session and challenge TTLs.
/// Bind from "Ssdid:Sessions" in appsettings.json.
/// </summary>
public class SessionStoreOptions
{
    public const string SectionName = "Ssdid:Sessions";

    /// <summary>Session sliding expiration in minutes. Default: 60 (1 hour).</summary>
    public int SessionTtlMinutes { get; set; } = 60;

    /// <summary>Challenge absolute expiration in minutes. Default: 5.</summary>
    public int ChallengeTtlMinutes { get; set; } = 5;

    /// <summary>Maximum concurrent sessions (in-memory store only). Default: 10,000.</summary>
    public int MaxSessions { get; set; } = 10_000;

    public TimeSpan SessionTtl => TimeSpan.FromMinutes(SessionTtlMinutes);
    public TimeSpan ChallengeTtl => TimeSpan.FromMinutes(ChallengeTtlMinutes);
}
