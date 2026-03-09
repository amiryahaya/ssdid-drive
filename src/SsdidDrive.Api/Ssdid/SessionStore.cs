using System.Collections.Concurrent;

namespace SsdidDrive.Api.Ssdid;

// TODO: Replace with IDistributedCache or Redis-backed implementation
// for horizontal scaling. The current in-memory store is single-instance only.

public class SessionStore : ISessionStore, ISseNotificationBus, IHostedService
{
    private readonly ConcurrentDictionary<string, ChallengeEntry> _challenges = new();
    private readonly ConcurrentDictionary<string, SessionEntry> _sessions = new();
    private record WaiterEntry(TaskCompletionSource<string> Tcs, DateTimeOffset CreatedAt);
    private readonly ConcurrentDictionary<string, WaiterEntry> _completionWaiters = new();
    private readonly ConcurrentDictionary<string, (string Secret, DateTimeOffset CreatedAt)> _subscriberSecrets = new();
    private readonly TimeProvider _clock;
    private long _sessionCount;
    private Timer? _gcTimer;

    public SessionStore(TimeProvider? clock = null)
    {
        _clock = clock ?? TimeProvider.System;
    }

    private static readonly TimeSpan ChallengeTtl = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SessionTtl = TimeSpan.FromHours(1);
    private static readonly TimeSpan GcInterval = TimeSpan.FromMinutes(1);
    private const int MaxSessions = 10_000;

    // ── Challenges ──

    public record ChallengeEntry(string Challenge, string KeyId, DateTimeOffset CreatedAt);

    public void CreateChallenge(string did, string purpose, string challenge, string keyId)
    {
        var key = $"{did}:{purpose}";
        _challenges[key] = new ChallengeEntry(challenge, keyId, _clock.GetUtcNow());
    }

    public ChallengeEntry? ConsumeChallenge(string did, string purpose)
    {
        var key = $"{did}:{purpose}";
        if (!_challenges.TryRemove(key, out var entry))
            return null;

        if (_clock.GetUtcNow() - entry.CreatedAt > ChallengeTtl)
            return null;

        return entry;
    }

    // ── Sessions ──

    private record SessionEntry(string Did, DateTimeOffset CreatedAt);

    public string? CreateSession(string did)
    {
        if (Interlocked.Read(ref _sessionCount) >= MaxSessions)
            return null;

        var token = SsdidCrypto.GenerateChallenge();

        if (_sessions.TryAdd(token, new SessionEntry(did, _clock.GetUtcNow())))
        {
            Interlocked.Increment(ref _sessionCount);
            return token;
        }

        return null; // Token collision (astronomically unlikely with 32 random bytes)
    }

    public string? GetSession(string token)
    {
        if (!_sessions.TryGetValue(token, out var entry))
            return null;

        if (_clock.GetUtcNow() - entry.CreatedAt > SessionTtl)
        {
            if (_sessions.TryRemove(token, out _))
                Interlocked.Decrement(ref _sessionCount);
            return null;
        }

        return entry.Did;
    }

    public void DeleteSession(string token)
    {
        if (_sessions.TryRemove(token, out _))
            Interlocked.Decrement(ref _sessionCount);
    }

    public int ActiveSessionCount => _sessions.Count;
    public int ActiveChallengeCount => _challenges.Count;

    internal void CreateSessionDirect(string did, string token)
    {
        if (_sessions.TryAdd(token, new SessionEntry(did, _clock.GetUtcNow())))
            Interlocked.Increment(ref _sessionCount);
    }

    // ── SSE subscriber secrets (ownership binding) ──

    public string CreateSubscriberSecret(string challengeId)
    {
        var secret = SsdidCrypto.GenerateChallenge();
        _subscriberSecrets[challengeId] = (secret, _clock.GetUtcNow());
        return secret;
    }

    public bool ValidateSubscriberSecret(string challengeId, string secret)
    {
        if (!_subscriberSecrets.TryGetValue(challengeId, out var entry))
            return false;

        if (_clock.GetUtcNow() - entry.CreatedAt > ChallengeTtl)
        {
            _subscriberSecrets.TryRemove(challengeId, out _);
            return false;
        }

        return string.Equals(entry.Secret, secret, StringComparison.Ordinal);
    }

    // ── SSE completion waiters ──

    public Task<string> WaitForCompletion(string challengeId, CancellationToken ct)
    {
        var entry = _completionWaiters.GetOrAdd(challengeId,
            _ => new WaiterEntry(
                new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously),
                _clock.GetUtcNow()));

        var reg = ct.Register(() =>
        {
            entry.Tcs.TrySetCanceled(ct);
            _completionWaiters.TryRemove(challengeId, out _);
        });

        _ = entry.Tcs.Task.ContinueWith(_ => reg.Dispose(), TaskScheduler.Default);

        return entry.Tcs.Task;
    }

    public bool NotifyCompletion(string challengeId, string sessionToken)
    {
        if (_completionWaiters.TryRemove(challengeId, out var entry))
            return entry.Tcs.TrySetResult(sessionToken);

        return false;
    }

    // ── IHostedService (garbage collection) ──

    public Task StartAsync(CancellationToken ct)
    {
        _gcTimer = new Timer(CollectExpired, null, GcInterval, GcInterval);
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken ct)
    {
        if (_gcTimer is not null)
            await _gcTimer.DisposeAsync();
    }

    private void CollectExpired(object? state)
    {
        var now = _clock.GetUtcNow();

        foreach (var (key, entry) in _challenges)
        {
            if (now - entry.CreatedAt > ChallengeTtl)
                _challenges.TryRemove(key, out _);
        }

        foreach (var (key, entry) in _sessions)
        {
            if (now - entry.CreatedAt > SessionTtl)
            {
                if (_sessions.TryRemove(key, out _))
                    Interlocked.Decrement(ref _sessionCount);
            }
        }

        foreach (var (key, entry) in _completionWaiters)
        {
            if (now - entry.CreatedAt > ChallengeTtl)
            {
                if (_completionWaiters.TryRemove(key, out var removed))
                    removed.Tcs.TrySetCanceled();
            }
        }

        foreach (var (key, entry) in _subscriberSecrets)
        {
            if (now - entry.CreatedAt > ChallengeTtl)
                _subscriberSecrets.TryRemove(key, out _);
        }
    }
}
