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
        _store = new RedisSessionStore(cache, _mux, NullLogger<RedisSessionStore>.Instance);
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

        var did = _store.GetSession(token);
        Assert.Equal("did:test:session", did);

        _store.DeleteSession(token);
        var gone = _store.GetSession(token);
        Assert.Null(gone);
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
}
