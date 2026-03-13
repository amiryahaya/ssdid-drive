namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Returned by <see cref="ISessionStore.ConsumeChallenge"/> with the original challenge payload.
/// </summary>
public record ChallengeEntry(string Challenge, string KeyId, DateTimeOffset CreatedAt);

/// <summary>
/// Manages authentication challenges and session lifecycle.
/// </summary>
public interface ISessionStore
{
    void CreateChallenge(string did, string purpose, string challenge, string keyId);
    ChallengeEntry? ConsumeChallenge(string did, string purpose);
    string? CreateSession(string did);
    string? GetSession(string token);
    void DeleteSession(string token);

    /// <summary>
    /// Invalidate all sessions for a given DID (used during recovery DID migration).
    /// </summary>
    void InvalidateSessionsForDid(string did);

    int ActiveSessionCount { get; }
    int ActiveChallengeCount { get; }
}
