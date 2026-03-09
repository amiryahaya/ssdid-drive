namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Manages authentication challenges and session lifecycle.
/// Extract to Redis-backed implementation for horizontal scaling.
/// </summary>
public interface ISessionStore
{
    void CreateChallenge(string did, string purpose, string challenge, string keyId);
    SessionStore.ChallengeEntry? ConsumeChallenge(string did, string purpose);
    string? CreateSession(string did);
    string? GetSession(string token);
    void DeleteSession(string token);

    int ActiveSessionCount { get; }
    int ActiveChallengeCount { get; }
}
