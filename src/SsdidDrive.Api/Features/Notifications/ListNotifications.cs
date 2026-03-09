using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Notifications;

public static class ListNotifications
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        [AsParameters] PaginationParams pagination,
        bool? unread_only,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var query = db.Notifications.Where(n => n.UserId == user.Id);

        if (unread_only == true)
            query = query.Where(n => !n.IsRead);

        var total = await query.CountAsync(ct);

        // Client-side ordering for SQLite compatibility in tests
        var notifications = (await query
            .Select(n => new
            {
                n.Id,
                n.UserId,
                n.Type,
                n.Title,
                n.Message,
                n.IsRead,
                n.ActionType,
                n.ActionResourceId,
                n.CreatedAt
            })
            .ToListAsync(ct))
            .OrderByDescending(n => n.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .ToList();

        return Results.Ok(new PagedResponse<object>(notifications, total, pagination.NormalizedPage, pagination.Take));
    }
}
