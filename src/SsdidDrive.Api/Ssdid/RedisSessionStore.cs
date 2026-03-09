using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Redis-backed session and challenge store for horizontal scaling.
/// Uses IDistributedCache for sessions/challenges, Redis pub/sub for SSE notifications,
/// and atomic Redis counters for O(1) metrics.
/// </summary>
public class RedisSessionStore : ISessionStore, ISseNotificationBus
{
    private readonly IDistributedCache _cache;
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisSessionStore> _logger;
    private readonly SessionStoreOptions _options;

    private const string ChallengePrefix = "ssdid:challenge:";
    private const string SessionPrefix = "ssdid:session:";
    private const string SubscriberSecretPrefix = "ssdid:subsecret:";
    private const string CompletionChannel = "ssdid:completion:";
    private const string SessionCountKey = "ssdid:count:sessions";
    private const string ChallengeCountKey = "ssdid:count:challenges";

    public RedisSessionStore(
        IDistributedCache cache,
        IConnectionMultiplexer redis,
        ILogger<RedisSessionStore> logger,
        IOptions<SessionStoreOptions> options)
    {
        _cache = cache;
        _redis = redis;
        _logger = logger;
        _options = options.Value;
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
            // Only increment counter if this is a new key (not overwriting an existing challenge).
            var existed = db.KeyExists(key);
            db.StringSet(key, json, _options.ChallengeTtl);
            if (!existed)
                db.StringIncrement(ChallengeCountKey);
        }
        catch (RedisConnectionException ex)
        {
            _logger.LogError(ex, "Redis unavailable for CreateChallenge");
            throw;
        }
    }

    public ChallengeEntry? ConsumeChallenge(string did, string purpose)
    {
        var key = $"{ChallengePrefix}{did}:{purpose}";

        try
        {
            var db = _redis.GetDatabase();
            var value = db.StringGetDelete(key);

            if (value.IsNullOrEmpty)
                return null;

            // Key existed and was deleted — decrement counter.
            db.StringDecrement(ChallengeCountKey);

            var data = JsonSerializer.Deserialize<ChallengeData>(value.ToString());
            if (data is null)
                return null;

            // Redis enforces the TTL set during StringSet — no manual expiry check needed.
            return new ChallengeEntry(data.Challenge, data.KeyId, data.CreatedAt);
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
                SlidingExpiration = _options.SessionTtl
            });

            var db = _redis.GetDatabase();
            db.StringIncrement(SessionCountKey);
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
            // Atomic delete — KeyDelete returns true only if the key existed.
            var db = _redis.GetDatabase();
            if (db.KeyDelete(key))
                db.StringDecrement(SessionCountKey);
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

        try
        {
            _cache.SetString(key, json, new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = _options.ChallengeTtl
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Redis unavailable for CreateSubscriberSecret");
            throw;
        }

        return secret;
    }

    public bool ValidateSubscriberSecret(string challengeId, string secret)
    {
        var key = $"{SubscriberSecretPrefix}{challengeId}";

        try
        {
            var json = _cache.GetString(key);
            if (json is null)
                return false;

            var data = JsonSerializer.Deserialize<SubscriberSecretData>(json);
            if (data is null)
                return false;

            return string.Equals(data.Secret, secret, StringComparison.Ordinal);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Redis unavailable for ValidateSubscriberSecret");
            return false;
        }
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

        // Register cancellation — only signal the TCS; unsubscribe is handled in finally.
        var reg = ct.Register(() => tcs.TrySetCanceled(ct));

        try
        {
            return await tcs.Task;
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

    // ── Metrics (O(1) atomic counters) ──
    //
    // These counters are approximate: they are incremented on create and decremented on
    // explicit delete/consume, but keys that expire via Redis TTL are not decremented.
    // Over time, counters may drift slightly above the true count. This is acceptable
    // for monitoring/metrics use. For exact counts, use SCAN-based counting (expensive).

    public int ActiveSessionCount
    {
        get
        {
            try
            {
                var db = _redis.GetDatabase();
                var value = db.StringGet(SessionCountKey);
                return value.IsNullOrEmpty ? 0 : Math.Max(0, (int)value);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to read active session count");
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
                var db = _redis.GetDatabase();
                var value = db.StringGet(ChallengeCountKey);
                return value.IsNullOrEmpty ? 0 : Math.Max(0, (int)value);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to read active challenge count");
                return -1;
            }
        }
    }

    // ── Internal method for test setup ──

    internal void CreateSessionDirect(string did, string token)
    {
        var key = $"{SessionPrefix}{token}";
        var entry = new SessionData(did, DateTimeOffset.UtcNow);
        var json = JsonSerializer.Serialize(entry);

        _cache.SetString(key, json, new DistributedCacheEntryOptions
        {
            SlidingExpiration = _options.SessionTtl
        });

        var db = _redis.GetDatabase();
        db.StringIncrement(SessionCountKey);
    }

    // ── Internal DTOs ──

    private record ChallengeData(string Challenge, string KeyId, DateTimeOffset CreatedAt);
    private record SessionData(string Did, DateTimeOffset CreatedAt);
    private record SubscriberSecretData(string Secret, DateTimeOffset CreatedAt);
}
