using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListNotificationLog
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/notifications", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        var pagination = new PaginationParams(page, pageSize);
        var total = await db.NotificationLogs.CountAsync(ct);
        var items = await db.NotificationLogs
            .OrderByDescending(n => n.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .Include(n => n.SentBy)
            .Select(n => new
            {
                n.Id, n.Scope, n.TargetId, n.Title, n.Message,
                n.RecipientCount, n.CreatedAt,
                SentByName = n.SentBy.DisplayName ?? n.SentBy.Did
            })
            .ToListAsync(ct);

        return Results.Ok(new PagedResponse<object>(items, total, pagination.NormalizedPage, pagination.Take));
    }
}
