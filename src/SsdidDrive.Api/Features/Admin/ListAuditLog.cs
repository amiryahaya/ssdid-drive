using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListAuditLog
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/audit-log", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        int? page,
        int? pageSize,
        CancellationToken ct)
    {
        var p = Math.Max(1, page ?? 1);
        var ps = Math.Clamp(pageSize ?? 50, 1, 200);

        var query = db.AuditLog
            .Include(e => e.Actor)
            .AsNoTracking();

        var total = await query.CountAsync(ct);

        var items = await query
            .OrderByDescending(e => e.CreatedAt)
            .Skip((p - 1) * ps)
            .Take(ps)
            .Select(e => new
            {
                id = e.Id,
                actor_id = e.ActorId,
                actor_name = e.Actor.DisplayName,
                action = e.Action,
                target_type = e.TargetType,
                target_id = e.TargetId,
                details = e.Details,
                created_at = e.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            items,
            total,
            page = p,
            page_size = ps
        });
    }
}
