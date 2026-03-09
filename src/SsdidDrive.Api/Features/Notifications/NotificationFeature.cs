namespace SsdidDrive.Api.Features.Notifications;

public static class NotificationFeature
{
    public static void MapNotificationFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/notifications").WithTags("Notifications");

        ListNotifications.Map(group);
        GetUnreadCount.Map(group);
        MarkAsRead.Map(group);
        MarkAllAsRead.Map(group);
        DeleteNotification.Map(group);
    }
}
