using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class NotificationService(AppDbContext db)
{
    public async Task CreateAsync(Guid userId, string type, string title, string message,
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
        await db.SaveChangesAsync(ct);
    }
}
