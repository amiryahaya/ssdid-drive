using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class AuthEvents
{
    private static readonly TimeSpan SseTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan KeepAliveInterval = TimeSpan.FromSeconds(30);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public static void MapAuthEvents(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/auth/ssdid/events", HandleSse)
            .RequireRateLimiting("auth")
            .WithMetadata(new SsdidPublicAttribute());
    }

    private static async Task HandleSse(
        HttpContext context,
        [FromQuery(Name = "challenge_id")] string? challengeId,
        [FromQuery(Name = "subscriber_secret")] string? subscriberSecret,
        ISseNotificationBus sseBus,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(challengeId))
        {
            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new { error = "challenge_id is required" }, JsonOptions, ct);
            return;
        }

        if (string.IsNullOrWhiteSpace(subscriberSecret) ||
            !sseBus.ValidateSubscriberSecret(challengeId, subscriberSecret))
        {
            context.Response.StatusCode = 403;
            await context.Response.WriteAsJsonAsync(new { error = "invalid subscriber_secret" }, JsonOptions, ct);
            return;
        }

        context.Response.Headers.ContentType = "text/event-stream";
        context.Response.Headers.CacheControl = "no-cache";
        context.Response.Headers.Connection = "keep-alive";
        context.Response.Headers["X-Accel-Buffering"] = "no";

        // Flush headers immediately so the client knows the SSE connection is established
        await context.Response.Body.FlushAsync(ct);

        using var timeoutCts = new CancellationTokenSource(SseTimeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct, timeoutCts.Token);

        try
        {
            var completionTask = sseBus.WaitForCompletion(challengeId, linkedCts.Token);

            // Send periodic keep-alive comments to prevent proxy idle timeouts
            while (!completionTask.IsCompleted)
            {
                var keepAlive = Task.Delay(KeepAliveInterval, linkedCts.Token);
                var finished = await Task.WhenAny(completionTask, keepAlive);

                if (finished == completionTask)
                    break;

                // Send SSE comment (ignored by EventSource clients, keeps connection alive)
                await context.Response.WriteAsync(": keep-alive\n\n", linkedCts.Token);
                await context.Response.Body.FlushAsync(linkedCts.Token);
            }

            var sessionToken = await completionTask;
            var data = JsonSerializer.Serialize(new { session_token = sessionToken }, JsonOptions);
            await context.Response.WriteAsync($"event: authenticated\ndata: {data}\n\n", linkedCts.Token);
            await context.Response.Body.FlushAsync(linkedCts.Token);
        }
        catch (OperationCanceledException)
        {
            if (timeoutCts.IsCancellationRequested && !ct.IsCancellationRequested)
            {
                var data = JsonSerializer.Serialize(new { reason = "timeout" }, JsonOptions);
                await context.Response.WriteAsync($"event: timeout\ndata: {data}\n\n", CancellationToken.None);
                await context.Response.Body.FlushAsync(CancellationToken.None);
            }
        }
    }
}
