using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace SsdidDrive.Api.Services;

public class WebAuthnChallengeStore
{
    private readonly ConcurrentDictionary<Guid, (string Challenge, DateTimeOffset CreatedAt)> _challenges = new();
    private static readonly TimeSpan ChallengeTimeout = TimeSpan.FromMinutes(5);

    public string CreateChallenge(Guid userId)
    {
        CleanupExpired();
        var challenge = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        _challenges[userId] = (challenge, DateTimeOffset.UtcNow);
        return challenge;
    }

    public string? ConsumeChallenge(Guid userId)
    {
        if (!_challenges.TryRemove(userId, out var entry))
            return null;
        if (DateTimeOffset.UtcNow - entry.CreatedAt > ChallengeTimeout)
            return null;
        return entry.Challenge;
    }

    private void CleanupExpired()
    {
        var cutoff = DateTimeOffset.UtcNow - ChallengeTimeout;
        foreach (var (key, value) in _challenges)
            if (value.CreatedAt < cutoff)
                _challenges.TryRemove(key, out _);
    }
}
