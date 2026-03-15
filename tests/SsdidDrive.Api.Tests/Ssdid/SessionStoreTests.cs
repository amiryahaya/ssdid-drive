using Microsoft.Extensions.Time.Testing;
using Ssdid.Sdk.Server.Session.InMemory;

namespace SsdidDrive.Api.Tests.Ssdid;

public class SessionStoreTests
{
    [Fact]
    public async Task WaitForCompletion_And_NotifyCompletion_Roundtrip()
    {
        var store = new InMemorySessionStore();
        var challengeId = "test-challenge-1";
        var expectedToken = "session-token-abc";

        var waitTask = store.WaitForCompletion(challengeId, CancellationToken.None);

        Assert.False(waitTask.IsCompleted);

        var notified = store.NotifyCompletion(challengeId, expectedToken);

        Assert.True(notified);

        var result = await waitTask;
        Assert.Equal(expectedToken, result);
    }

    [Fact]
    public async Task WaitForCompletion_TimesOut_WhenNoCompletion()
    {
        var store = new InMemorySessionStore();
        var challengeId = "test-challenge-timeout";

        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        await Assert.ThrowsAsync<TaskCanceledException>(
            () => store.WaitForCompletion(challengeId, cts.Token));
    }

    [Fact]
    public async Task WaitForCompletion_Cancels_WhenTokenCancelled()
    {
        var store = new InMemorySessionStore();
        var challengeId = "test-challenge-cancel";

        using var cts = new CancellationTokenSource();
        var waitTask = store.WaitForCompletion(challengeId, cts.Token);

        Assert.False(waitTask.IsCompleted);

        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => waitTask);
    }

    [Fact]
    public void NotifyCompletion_ReturnsFalse_WhenNoWaiter()
    {
        var store = new InMemorySessionStore();

        var result = store.NotifyCompletion("nonexistent-challenge", "token");

        Assert.False(result);
    }

    [Fact]
    public async Task WaitForCompletion_MultipleWaiters_SameChallengeId_ShareResult()
    {
        var store = new InMemorySessionStore();
        var challengeId = "shared-challenge";
        var expectedToken = "shared-token";

        var wait1 = store.WaitForCompletion(challengeId, CancellationToken.None);
        var wait2 = store.WaitForCompletion(challengeId, CancellationToken.None);

        store.NotifyCompletion(challengeId, expectedToken);

        var result1 = await wait1;
        var result2 = await wait2;
        Assert.Equal(expectedToken, result1);
        Assert.Equal(expectedToken, result2);
    }

    [Fact]
    public void NotifyCompletion_SecondCall_ReturnsFalse()
    {
        var store = new InMemorySessionStore();
        var challengeId = "once-challenge";

        _ = store.WaitForCompletion(challengeId, CancellationToken.None);

        Assert.True(store.NotifyCompletion(challengeId, "token1"));
        Assert.False(store.NotifyCompletion(challengeId, "token2"));
    }

    // ── TTL tests ──────────────────────────────────────────────────────

    [Fact]
    public void GetSession_ExpiredSession_ReturnsNull()
    {
        var clock = new FakeTimeProvider(DateTimeOffset.UtcNow);
        var store = new InMemorySessionStore(clock: clock);
        var did = "did:ssdid:expired-session";
        var token = store.CreateSession(did);
        Assert.NotNull(token);

        // Advance past the 1-hour session TTL
        clock.Advance(TimeSpan.FromHours(1) + TimeSpan.FromSeconds(1));

        var result = store.GetSession(token!);
        Assert.Null(result);
    }

    [Fact]
    public void GetSession_SlidingExpiration_ExtendsLifetime()
    {
        var clock = new FakeTimeProvider(DateTimeOffset.UtcNow);
        var store = new InMemorySessionStore(clock: clock);
        var did = "did:ssdid:sliding-test";
        var token = store.CreateSession(did);
        Assert.NotNull(token);

        // Advance 50 minutes (within the 60-min window) and access — should slide the window.
        clock.Advance(TimeSpan.FromMinutes(50));
        var mid = store.GetSession(token!);
        Assert.Equal(did, mid);

        // Advance another 50 minutes (100 min total from creation, but only 50 from last access).
        clock.Advance(TimeSpan.FromMinutes(50));
        var still = store.GetSession(token!);
        Assert.Equal(did, still);

        // Now advance past the sliding window without accessing.
        clock.Advance(TimeSpan.FromHours(1) + TimeSpan.FromSeconds(1));
        var expired = store.GetSession(token!);
        Assert.Null(expired);
    }

    [Fact]
    public void ConsumeChallenge_ExpiredChallenge_ReturnsNull()
    {
        var clock = new FakeTimeProvider(DateTimeOffset.UtcNow);
        var store = new InMemorySessionStore(clock: clock);
        var did = "did:ssdid:expired-challenge";
        var purpose = "register";

        store.CreateChallenge(did, purpose, "challenge-data", "key-1");

        // Advance past the 5-minute challenge TTL
        clock.Advance(TimeSpan.FromMinutes(5) + TimeSpan.FromSeconds(1));

        var result = store.ConsumeChallenge(did, purpose);
        Assert.Null(result);
    }

    [Fact]
    public void CreateSession_MaxSessionsCap_ReturnsNull()
    {
        var store = new InMemorySessionStore();

        // Fill up to MaxSessions (10,000) using the internal direct method
        for (var i = 0; i < 10_000; i++)
            store.CreateSessionDirect($"did:ssdid:cap-{i}", $"token-{i}");

        // The next session should be rejected
        var result = store.CreateSession("did:ssdid:one-too-many");
        Assert.Null(result);
    }

    [Fact]
    public void GetSession_ValidSession_ReturnsDid()
    {
        var store = new InMemorySessionStore();
        var did = "did:ssdid:ttl-test";
        var token = store.CreateSession(did);

        Assert.NotNull(token);

        var result = store.GetSession(token!);
        Assert.Equal(did, result);
    }

    [Fact]
    public void GetSession_DeletedSession_ReturnsNull()
    {
        var store = new InMemorySessionStore();
        var did = "did:ssdid:deleted-session";
        var token = store.CreateSession(did);
        Assert.NotNull(token);

        store.DeleteSession(token!);

        var result = store.GetSession(token!);
        Assert.Null(result);
    }

    [Fact]
    public void ConsumeChallenge_ValidChallenge_ReturnsEntry()
    {
        var store = new InMemorySessionStore();
        var did = "did:ssdid:challenge-ttl";
        var purpose = "register";

        store.CreateChallenge(did, purpose, "test-challenge-data", "key-1");

        var result = store.ConsumeChallenge(did, purpose);
        Assert.NotNull(result);
        Assert.Equal("test-challenge-data", result!.Challenge);
        Assert.Equal("key-1", result.KeyId);
    }

    [Fact]
    public void ConsumeChallenge_AlreadyConsumed_ReturnsNull()
    {
        var store = new InMemorySessionStore();
        var did = "did:ssdid:challenge-double";
        var purpose = "register";

        store.CreateChallenge(did, purpose, "one-time-challenge", "key-1");

        var first = store.ConsumeChallenge(did, purpose);
        Assert.NotNull(first);

        // Second consume should return null (already consumed)
        var second = store.ConsumeChallenge(did, purpose);
        Assert.Null(second);
    }

    [Fact]
    public void GetSession_NonExistentToken_ReturnsNull()
    {
        var store = new InMemorySessionStore();
        var result = store.GetSession("nonexistent-token");
        Assert.Null(result);
    }

    [Fact]
    public void ConsumeChallenge_NonExistent_ReturnsNull()
    {
        var store = new InMemorySessionStore();
        var result = store.ConsumeChallenge("did:ssdid:nonexistent", "register");
        Assert.Null(result);
    }
}
