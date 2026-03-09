using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using StackExchange.Redis;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Redis-backed session and challenge store for horizontal scaling.
/// Uses IDistributedCache for sessions/challenges and Redis pub/sub for SSE notifications.
/// </summary>
public class RedisSessionStore : ISessionStore, ISseNotificationBus
{
    private readonly IDistributedCache _cache;
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisSessionStore> _logger;

    private static readonly TimeSpan ChallengeTtl = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SessionTtl = TimeSpan.FromHours(1);

    private const string ChallengePrefix = "ssdid:challenge:";
    private const string SessionPrefix = "ssdid:session:";
    private const string SubscriberSecretPrefix = "ssdid:subsecret:";
    private const string CompletionChannel = "ssdid:completion:";

    public RedisSessionStore(
        IDistributedCache cache,
        IConnectionMultiplexer redis,
        ILogger<RedisSessionStore> logger)
    {
        _cache = cache;
        _redis = redis;
        _logger = logger;
    }

    // ── Challenges ──

    public void CreateChallenge(string did, string purpose, string challenge, string keyId)
    {
        var key = $"{ChallengePrefix}{did}:{purpose}";
        var entry = new ChallengeData(challenge, keyId, DateTimeOffset.UtcNow);
        var json = JsonSerializer.Serialize(entry);

        try
        {
            var db = _redis.GetDatabase();
            db.StringSet(key, json, ChallengeTtl);
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for CreateChallenge");
            throw;
        }
    }

    public SessionStore.ChallengeEntry? ConsumeChallenge(string did, string purpose)
    {
        var key = $"{ChallengePrefix}{did}:{purpose}";

        try
        {
            var db = _redis.GetDatabase();
            var value = db.StringGetDelete(key);

            if (value.IsNullOrEmpty)
                return null;

            var data = JsonSerializer.Deserialize<ChallengeData>(value.ToString());
            if (data is null)
                return null;

            if (DateTimeOffset.UtcNow - data.CreatedAt > ChallengeTtl)
                return null;

            return new SessionStore.ChallengeEntry(data.Challenge, data.KeyId, data.CreatedAt);
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for ConsumeChallenge");
            return null;
        }
    }

    // ── Sessions ──

    public string? CreateSession(string did)
    {
        var token = SsdidCrypto.GenerateChallenge();
        var key = $"{SessionPrefix}{token}";
        var entry = new SessionData(did, DateTimeOffset.UtcNow);
        var json = JsonSerializer.Serialize(entry);

        try
        {
            _cache.SetString(key, json, new DistributedCacheEntryOptions
            {
                SlidingExpiration = SessionTtl
            });
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for CreateSession");
            return null;
        }

        return token;
    }

    public string? GetSession(string token)
    {
        var key = $"{SessionPrefix}{token}";

        try
        {
            var json = _cache.GetString(key);
            if (json is null)
                return null;

            var data = JsonSerializer.Deserialize<SessionData>(json);
            return data?.Did;
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for GetSession");
            return null;
        }
    }

    public void DeleteSession(string token)
    {
        var key = $"{SessionPrefix}{token}";

        try
        {
            _cache.Remove(key);
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for DeleteSession");
        }
    }

    // ── SSE subscriber secrets ──

    public string CreateSubscriberSecret(string challengeId)
    {
        var secret = SsdidCrypto.GenerateChallenge();
        var key = $"{SubscriberSecretPrefix}{challengeId}";

        var entry = new SubscriberSecretData(secret, DateTimeOffset.UtcNow);
        var json = JsonSerializer.Serialize(entry);

        _cache.SetString(key, json, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = ChallengeTtl
        });

        return secret;
    }

    public bool ValidateSubscriberSecret(string challengeId, string secret)
    {
        var key = $"{SubscriberSecretPrefix}{challengeId}";
        var json = _cache.GetString(key);

        if (json is null)
            return false;

        var data = JsonSerializer.Deserialize<SubscriberSecretData>(json);
        if (data is null)
            return false;

        if (DateTimeOffset.UtcNow - data.CreatedAt > ChallengeTtl)
        {
            _cache.Remove(key);
            return false;
        }

        return string.Equals(data.Secret, secret, StringComparison.Ordinal);
    }

    // ── SSE completion (Redis pub/sub) ──

    public async Task<string> WaitForCompletion(string challengeId, CancellationToken ct)
    {
        var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var channel = RedisChannel.Literal($"{CompletionChannel}{challengeId}");
        var subscriber = _redis.GetSubscriber();

        await subscriber.SubscribeAsync(channel, (_, message) =>
        {
            if (message.HasValue)
                tcs.TrySetResult(message!);
        });

        var reg = ct.Register(() =>
        {
            tcs.TrySetCanceled(ct);
            subscriber.Unsubscribe(channel);
        });

        try
        {
            var result = await tcs.Task;
            return result;
        }
        finally
        {
            reg.Dispose();
            await subscriber.UnsubscribeAsync(channel);
        }
    }

    public bool NotifyCompletion(string challengeId, string sessionToken)
    {
        try
        {
            var channel = RedisChannel.Literal($"{CompletionChannel}{challengeId}");
            var subscriber = _redis.GetSubscriber();
            var receivers = subscriber.Publish(channel, sessionToken);
            return receivers > 0;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish completion for challenge {ChallengeId}", challengeId);
            return false;
        }
    }

    // ── Metrics ──

    public int ActiveSessionCount
    {
        get
        {
            try
            {
                return CountKeysByPattern($"{SessionPrefix}*");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to count active sessions");
                return -1;
            }
        }
    }

    public int ActiveChallengeCount
    {
        get
        {
            try
            {
                return CountKeysByPattern($"{ChallengePrefix}*");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to count active challenges");
                return -1;
            }
        }
    }

    private int CountKeysByPattern(string pattern)
    {
        var count = 0;
        foreach (var endpoint in _redis.GetEndPoints())
        {
            var server = _redis.GetServer(endpoint);
            foreach (var _ in server.Keys(pattern: pattern, pageSize: 250))
                count++;
        }
        return count;
    }

    // ── Internal method for test setup ──

    internal void CreateSessionDirect(string did, string token)
    {
        var key = $"{SessionPrefix}{token}";
        var entry = new SessionData(did, DateTimeOffset.UtcNow);
        var json = JsonSerializer.Serialize(entry);

        _cache.SetString(key, json, new DistributedCacheEntryOptions
        {
            SlidingExpiration = SessionTtl
        });
    }

    // ── Internal DTOs ──

    private record ChallengeData(string Challenge, string KeyId, DateTimeOffset CreatedAt);
    private record SessionData(string Did, DateTimeOffset CreatedAt);
    private record SubscriberSecretData(string Secret, DateTimeOffset CreatedAt);
}
