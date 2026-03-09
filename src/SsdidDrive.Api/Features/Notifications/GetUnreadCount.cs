using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Notifications;

public static class GetUnreadCount
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/unread-count", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var count = await db.Notifications
            .CountAsync(n => n.UserId == user.Id && !n.IsRead, ct);

        return Results.Ok(new { count });
    }
}
