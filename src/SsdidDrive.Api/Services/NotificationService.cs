using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

/// <summary>
/// Creates notification entities and adds them to the DbContext.
/// The caller is responsible for calling <see cref="AppDbContext.SaveChangesAsync(CancellationToken)"/>
/// to persist the notification (typically as part of the same transaction as the triggering operation).
/// </summary>
public class NotificationService(AppDbContext db)
{
    public Task CreateAsync(Guid userId, string type, string title, string message,
        string? actionType = null, string? actionResourceId = null, CancellationToken ct = default)
    {
        var notification = new Notification
        {
            UserId = userId,
            Type = type,
            Title = title,
            Message = message,
            ActionType = actionType,
            ActionResourceId = actionResourceId,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.Notifications.Add(notification);
        return Task.CompletedTask;
    }
}
