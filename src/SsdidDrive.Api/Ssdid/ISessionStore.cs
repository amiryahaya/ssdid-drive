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
    /// Both <see cref="SessionStore"/> and <see cref="RedisSessionStore"/> store the session value
    /// as a plain string and compare with <see cref="StringComparison.Ordinal"/>, so this method
    /// works equally well with DID strings and UUID strings (e.g. <c>Account.Id.ToString()</c>).
    /// </summary>
    void InvalidateSessionsForDid(string did);

    /// <summary>Alias for <see cref="InvalidateSessionsForDid"/> — works for any session value (DID or Account.Id).</summary>
    void InvalidateSessionsForAccount(Guid accountId) => InvalidateSessionsForDid(accountId.ToString());

    int ActiveSessionCount { get; }
    int ActiveChallengeCount { get; }
}
