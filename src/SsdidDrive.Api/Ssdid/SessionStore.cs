using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// In-memory session and challenge store for single-instance deployments.
/// Uses sliding expiration for sessions (matching Redis store semantics).
/// </summary>
public class SessionStore : ISessionStore, ISseNotificationBus, IHostedService
{
    private readonly ConcurrentDictionary<string, ChallengeEntry> _challenges = new();
    private readonly ConcurrentDictionary<string, SessionEntry> _sessions = new();
    private record WaiterEntry(TaskCompletionSource<string> Tcs, DateTimeOffset CreatedAt);
    private readonly ConcurrentDictionary<string, WaiterEntry> _completionWaiters = new();
    private readonly ConcurrentDictionary<string, (string Secret, DateTimeOffset CreatedAt)> _subscriberSecrets = new();
    private readonly TimeProvider _clock;
    private readonly SessionStoreOptions _options;
    private long _sessionCount;
    private Timer? _gcTimer;

    private static readonly TimeSpan GcInterval = TimeSpan.FromMinutes(1);

    public SessionStore(IOptions<SessionStoreOptions>? options = null, TimeProvider? clock = null)
    {
        _clock = clock ?? TimeProvider.System;
        _options = options?.Value ?? new SessionStoreOptions();
    }

    // ── Challenges ──

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

        if (_clock.GetUtcNow() - entry.CreatedAt > _options.ChallengeTtl)
            return null;

        return entry;
    }

    // ── Sessions (sliding expiration) ──

    private class SessionEntry
    {
        public string Did { get; }
        private long _lastAccessedTicks;

        public SessionEntry(string did, DateTimeOffset lastAccessed)
        {
            Did = did;
            _lastAccessedTicks = lastAccessed.UtcTicks;
        }

        public DateTimeOffset LastAccessedAt =>
            new(Interlocked.Read(ref _lastAccessedTicks), TimeSpan.Zero);

        public void Touch(DateTimeOffset now) =>
            Interlocked.Exchange(ref _lastAccessedTicks, now.UtcTicks);
    }

    public string? CreateSession(string did)
    {
        // Pre-increment to reserve a slot, then roll back if TryAdd fails.
        var count = Interlocked.Increment(ref _sessionCount);
        if (count > _options.MaxSessions)
        {
            Interlocked.Decrement(ref _sessionCount);
            return null;
        }

        var token = SsdidCrypto.GenerateChallenge();

        if (_sessions.TryAdd(token, new SessionEntry(did, _clock.GetUtcNow())))
            return token;

        // Token collision (astronomically unlikely with 32 random bytes) — release slot.
        Interlocked.Decrement(ref _sessionCount);
        return null;
    }

    public string? GetSession(string token)
    {
        if (!_sessions.TryGetValue(token, out var entry))
            return null;

        var now = _clock.GetUtcNow();
        if (now - entry.LastAccessedAt > _options.SessionTtl)
        {
            if (_sessions.TryRemove(token, out _))
                Interlocked.Decrement(ref _sessionCount);
            return null;
        }

        // Slide the expiration window forward on each access.
        entry.Touch(now);
        return entry.Did;
    }

    public void DeleteSession(string token)
    {
        if (_sessions.TryRemove(token, out _))
            Interlocked.Decrement(ref _sessionCount);
    }

    public void InvalidateSessionsForDid(string did)
    {
        foreach (var (token, entry) in _sessions)
        {
            if (string.Equals(entry.Did, did, StringComparison.Ordinal))
            {
                if (_sessions.TryRemove(token, out _))
                    Interlocked.Decrement(ref _sessionCount);
            }
        }
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

        if (_clock.GetUtcNow() - entry.CreatedAt > _options.ChallengeTtl)
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
            if (now - entry.CreatedAt > _options.ChallengeTtl)
                _challenges.TryRemove(key, out _);
        }

        foreach (var (key, entry) in _sessions)
        {
            if (now - entry.LastAccessedAt > _options.SessionTtl)
            {
                if (_sessions.TryRemove(key, out _))
                    Interlocked.Decrement(ref _sessionCount);
            }
        }

        foreach (var (key, entry) in _completionWaiters)
        {
            if (now - entry.CreatedAt > _options.ChallengeTtl)
            {
                if (_completionWaiters.TryRemove(key, out var removed))
                    removed.Tcs.TrySetCanceled();
            }
        }

        foreach (var (key, entry) in _subscriberSecrets)
        {
            if (now - entry.CreatedAt > _options.ChallengeTtl)
                _subscriberSecrets.TryRemove(key, out _);
        }
    }
}
