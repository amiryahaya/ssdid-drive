using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class PushServiceTests
{
    private static PushService CreateService(
        HttpMessageHandler handler, string appId = "", string apiKey = "")
    {
        var httpClient = new HttpClient(handler);
        var options = Options.Create(new OneSignalOptions { AppId = appId, ApiKey = apiKey });
        var logger = NullLogger<PushService>.Instance;
        return new PushService(httpClient, options, logger);
    }

    // ── 1. Disabled when no config → does not call HTTP ─────────────────

    [Fact]
    public async Task SendToUsersAsync_DisabledWhenNoConfig_DoesNotCallHttp()
    {
        var handler = new TrackingHandler();
        var sut = CreateService(handler);

        await sut.SendToUsersAsync(["user-1"], "Title", "Message");

        Assert.Equal(0, handler.CallCount);
    }

    // ── 2. Empty user list → does not call HTTP ─────────────────────────

    [Fact]
    public async Task SendToUsersAsync_EmptyList_DoesNotCallHttp()
    {
        var handler = new TrackingHandler();
        var sut = CreateService(handler, appId: "app-123", apiKey: "key-456");

        await sut.SendToUsersAsync([], "Title", "Message");

        Assert.Equal(0, handler.CallCount);
    }

    // ── 3. HTTP failure → does not throw ────────────────────────────────

    [Fact]
    public async Task SendToUsersAsync_HttpFailure_DoesNotThrow()
    {
        var handler = new TrackingHandler(HttpStatusCode.InternalServerError);
        var sut = CreateService(handler, appId: "app-123", apiKey: "key-456");

        var exception = await Record.ExceptionAsync(() =>
            sut.SendToUsersAsync(["user-1"], "Title", "Message"));

        Assert.Null(exception);
        Assert.Equal(1, handler.CallCount);
    }

    // ── 4. Broadcast disabled when no config → does not call HTTP ───────

    [Fact]
    public async Task BroadcastAsync_DisabledWhenNoConfig_DoesNotCallHttp()
    {
        var handler = new TrackingHandler();
        var sut = CreateService(handler);

        await sut.BroadcastAsync("Title", "Message");

        Assert.Equal(0, handler.CallCount);
    }

    // ── 5. Broadcast HTTP failure → does not throw ──────────────────────

    [Fact]
    public async Task BroadcastAsync_HttpFailure_DoesNotThrow()
    {
        var handler = new TrackingHandler(HttpStatusCode.InternalServerError);
        var sut = CreateService(handler, appId: "app-123", apiKey: "key-456");

        var exception = await Record.ExceptionAsync(() =>
            sut.BroadcastAsync("Title", "Message"));

        Assert.Null(exception);
        Assert.Equal(1, handler.CallCount);
    }

    /// <summary>
    /// A mock HttpMessageHandler that tracks calls and returns a configurable status code.
    /// </summary>
    private class TrackingHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode _statusCode;
        private int _callCount;

        public int CallCount => _callCount;

        public TrackingHandler(HttpStatusCode statusCode = HttpStatusCode.OK)
        {
            _statusCode = statusCode;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref _callCount);
            return Task.FromResult(new HttpResponseMessage(_statusCode)
            {
                Content = new StringContent("{}")
            });
        }
    }
}
