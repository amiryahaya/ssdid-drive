using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Notifications;

public static class MarkAllAsRead
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/read-all", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var unread = await db.Notifications
            .Where(n => n.UserId == user.Id && !n.IsRead)
            .ToListAsync(ct);

        foreach (var n in unread)
            n.IsRead = true;

        await db.SaveChangesAsync(ct);

        return Results.Ok(new { count = unread.Count });
    }
}
