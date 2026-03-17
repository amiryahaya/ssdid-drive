using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

/// <summary>
/// Creates notification entities and adds them to the DbContext.
/// The caller is responsible for calling <see cref="AppDbContext.SaveChangesAsync(CancellationToken)"/>
/// to persist the notification (typically as part of the same transaction as the triggering operation).
/// </summary>
public class NotificationService(AppDbContext db, PushService pushService)
{
    /// <summary>
    /// Creates an in-app notification and optionally sends a push via OneSignal.
    /// Set <paramref name="skipPush"/> to true when the caller handles push separately (e.g., broadcast).
    /// </summary>
    public Task CreateAsync(Guid userId, string type, string title, string message,
        string? actionType = null, string? actionResourceId = null,
        bool skipPush = false, CancellationToken ct = default)
    {
        db.Notifications.Add(new Notification
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Type = type,
            Title = title,
            Message = message,
            ActionType = actionType,
            ActionResourceId = actionResourceId,
            CreatedAt = DateTimeOffset.UtcNow
        });

        if (!skipPush)
        {
            // Fire-and-forget push notification (non-blocking).
            // Use CancellationToken.None — the HTTP request token would cancel this prematurely.
            _ = pushService.SendToUsersAsync(
                [userId.ToString()], title, message, actionType, actionResourceId, CancellationToken.None);
        }

        return Task.CompletedTask;
    }
}
