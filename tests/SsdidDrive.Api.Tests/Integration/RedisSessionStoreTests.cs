using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SsdidDrive.Api.Ssdid;
using StackExchange.Redis;
using Testcontainers.Redis;

namespace SsdidDrive.Api.Tests.Integration;

public class RedisSessionStoreIntegrationTests : IAsyncLifetime
{
    private readonly RedisContainer _redis = new RedisBuilder()
        .WithImage("redis:7-alpine")
        .Build();

    private RedisSessionStore _store = null!;
    private IConnectionMultiplexer _mux = null!;

    public async ValueTask InitializeAsync()
    {
        await _redis.StartAsync();
        _mux = await ConnectionMultiplexer.ConnectAsync(_redis.GetConnectionString());
        var cache = new RedisCache(Options.Create(new RedisCacheOptions
        {
            Configuration = _redis.GetConnectionString(),
            InstanceName = ""
        }));
        _store = new RedisSessionStore(
            cache, _mux,
            NullLogger<RedisSessionStore>.Instance,
            Options.Create(new SessionStoreOptions()));
    }

    public async ValueTask DisposeAsync()
    {
        _mux.Dispose();
        await _redis.DisposeAsync();
    }

    [Fact]
    public void Challenge_CreateAndConsume_Works()
    {
        _store.CreateChallenge("did:test:redis", "register", "ch123", "key1");
        var entry = _store.ConsumeChallenge("did:test:redis", "register");
        Assert.NotNull(entry);
        Assert.Equal("ch123", entry.Challenge);
        Assert.Equal("key1", entry.KeyId);
    }

    [Fact]
    public void Challenge_DoubleConsume_ReturnsNull()
    {
        _store.CreateChallenge("did:test:double", "register", "ch456", "key2");
        _store.ConsumeChallenge("did:test:double", "register");
        var second = _store.ConsumeChallenge("did:test:double", "register");
        Assert.Null(second);
    }

    [Fact]
    public void Session_CreateGetDelete_Works()
    {
        var token = _store.CreateSession("did:test:session");
        Assert.NotNull(token);

        var did = _store.GetSession(token!);
        Assert.Equal("did:test:session", did);

        _store.DeleteSession(token!);
        var gone = _store.GetSession(token!);
        Assert.Null(gone);
    }

    [Fact]
    public void Session_CreateSessionDirect_Works()
    {
        _store.CreateSessionDirect("did:test:direct", "direct-token-123");
        var did = _store.GetSession("direct-token-123");
        Assert.Equal("did:test:direct", did);
    }

    [Fact]
    public void SubscriberSecret_CreateAndValidate_Works()
    {
        var challengeId = Guid.NewGuid().ToString();
        var secret = _store.CreateSubscriberSecret(challengeId);
        Assert.NotNull(secret);

        var valid = _store.ValidateSubscriberSecret(challengeId, secret);
        Assert.True(valid);

        var invalid = _store.ValidateSubscriberSecret(challengeId, "wrong-secret");
        Assert.False(invalid);
    }

    [Fact]
    public async Task PubSub_NotifyAndWait_Works()
    {
        var challengeId = Guid.NewGuid().ToString();
        var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var waitTask = _store.WaitForCompletion(challengeId, cts.Token);

        // Small delay for subscriber to connect
        await Task.Delay(200);
        var published = _store.NotifyCompletion(challengeId, "session-token-123");
        Assert.True(published);

        var result = await waitTask;
        Assert.Equal("session-token-123", result);
    }

    [Fact]
    public void ActiveSessionCount_ReturnsCorrectCount()
    {
        var token1 = _store.CreateSession("did:test:count-1");
        var token2 = _store.CreateSession("did:test:count-2");
        Assert.NotNull(token1);
        Assert.NotNull(token2);

        var count = _store.ActiveSessionCount;
        Assert.True(count >= 2, $"Expected at least 2 sessions, got {count}");
    }

    [Fact]
    public void ActiveChallengeCount_ReturnsCorrectCount()
    {
        var uniqueDid = $"did:test:chalcount-{Guid.NewGuid():N}";
        _store.CreateChallenge(uniqueDid, "purpose1", "ch1", "k1");
        _store.CreateChallenge(uniqueDid, "purpose2", "ch2", "k2");

        var count = _store.ActiveChallengeCount;
        Assert.True(count >= 2, $"Expected at least 2 challenges, got {count}");
    }

    [Fact]
    public void ActiveSessionCount_DecreasesAfterDelete()
    {
        var token = _store.CreateSession("did:test:count-delete");
        Assert.NotNull(token);

        var before = _store.ActiveSessionCount;
        _store.DeleteSession(token!);
        var after = _store.ActiveSessionCount;

        Assert.True(after < before, $"Expected count to decrease: before={before}, after={after}");
    }

    [Fact]
    public void Session_UsesSlidingExpiration()
    {
        var token = _store.CreateSession("did:test:sliding");
        Assert.NotNull(token);

        var db = _mux.GetDatabase();
        var ttl = db.KeyTimeToLive($"ssdid:session:{token}");
        Assert.NotNull(ttl);
        Assert.True(ttl.Value.TotalMinutes > 50, "Session TTL should be close to 1 hour");
    }

    [Fact]
    public async Task WaitForCompletion_Cancellation_ThrowsOperationCanceledException()
    {
        var challengeId = Guid.NewGuid().ToString();
        using var cts = new CancellationTokenSource();

        var waitTask = _store.WaitForCompletion(challengeId, cts.Token);

        await cts.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => waitTask);
    }

    [Fact]
    public void NotifyCompletion_NoSubscriber_ReturnsFalse()
    {
        var result = _store.NotifyCompletion(Guid.NewGuid().ToString(), "some-token");
        Assert.False(result);
    }

    [Fact]
    public void Session_KeyStoredWithoutDoubledPrefix()
    {
        var token = _store.CreateSession("did:test:prefix");
        Assert.NotNull(token);

        var db = _mux.GetDatabase();
        var correctKey = (RedisKey)$"ssdid:session:{token}";
        var doubledKey = (RedisKey)$"ssdid:ssdid:session:{token}";

        Assert.True(db.KeyExists(correctKey), "Key should exist with single ssdid: prefix");
        Assert.False(db.KeyExists(doubledKey), "Key must not exist with doubled ssdid:ssdid: prefix");
    }

    [Fact]
    public void ActiveSessionCount_ExactCount_AfterIsolatedOperations()
    {
        // Flush the DB so prior test data does not pollute the exact count assertion.
        var server = _mux.GetServer(_mux.GetEndPoints().First());
        server.FlushDatabase();

        _store.CreateSession("did:test:exact-1");
        _store.CreateSession("did:test:exact-2");
        _store.CreateSession("did:test:exact-3");

        Assert.Equal(3, _store.ActiveSessionCount);
    }

    [Fact]
    public void ActiveChallengeCount_DecreasesAfterConsume()
    {
        var server = _mux.GetServer(_mux.GetEndPoints().First());
        server.FlushDatabase();

        _store.CreateChallenge("did:test:chal-dec", "p1", "ch1", "k1");
        _store.CreateChallenge("did:test:chal-dec", "p2", "ch2", "k2");

        Assert.Equal(2, _store.ActiveChallengeCount);

        _store.ConsumeChallenge("did:test:chal-dec", "p1");
        Assert.Equal(1, _store.ActiveChallengeCount);
    }
}
