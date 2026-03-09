using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Ssdid;

public class SessionStoreTests
{
    [Fact]
    public async Task WaitForCompletion_And_NotifyCompletion_Roundtrip()
    {
        var store = new SessionStore();
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
        var store = new SessionStore();
        var challengeId = "test-challenge-timeout";

        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        await Assert.ThrowsAsync<TaskCanceledException>(
            () => store.WaitForCompletion(challengeId, cts.Token));
    }

    [Fact]
    public async Task WaitForCompletion_Cancels_WhenTokenCancelled()
    {
        var store = new SessionStore();
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
        var store = new SessionStore();

        var result = store.NotifyCompletion("nonexistent-challenge", "token");

        Assert.False(result);
    }

    [Fact]
    public async Task WaitForCompletion_MultipleWaiters_SameChallengeId_ShareResult()
    {
        var store = new SessionStore();
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
        var store = new SessionStore();
        var challengeId = "once-challenge";

        _ = store.WaitForCompletion(challengeId, CancellationToken.None);

        Assert.True(store.NotifyCompletion(challengeId, "token1"));
        Assert.False(store.NotifyCompletion(challengeId, "token2"));
    }

    // ── TTL tests ──────────────────────────────────────────────────────
    // NOTE: SessionStore uses DateTimeOffset.UtcNow internally with no clock
    // abstraction, so we cannot easily backdate sessions or challenges in unit
    // tests without refactoring. The tests below verify correctness for the
    // non-expired path (which is still valuable). True TTL testing would require
    // injecting a TimeProvider/IClock into SessionStore.

    [Fact]
    public void GetSession_ValidSession_ReturnsDid()
    {
        var store = new SessionStore();
        var did = "did:ssdid:ttl-test";
        var token = store.CreateSession(did);

        Assert.NotNull(token);

        var result = store.GetSession(token!);
        Assert.Equal(did, result);
    }

    [Fact]
    public void GetSession_DeletedSession_ReturnsNull()
    {
        var store = new SessionStore();
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
        var store = new SessionStore();
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
        var store = new SessionStore();
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
        var store = new SessionStore();
        var result = store.GetSession("nonexistent-token");
        Assert.Null(result);
    }

    [Fact]
    public void ConsumeChallenge_NonExistent_ReturnsNull()
    {
        var store = new SessionStore();
        var result = store.ConsumeChallenge("did:ssdid:nonexistent", "register");
        Assert.Null(result);
    }
}
