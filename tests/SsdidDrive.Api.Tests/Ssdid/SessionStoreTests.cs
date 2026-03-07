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
}
