using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListAuditLog
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/audit-log", Handle);

    private static async Task<IResult> Handle(
        [AsParameters] PaginationParams pagination,
        string? actor,
        string? action,
        DateTimeOffset? from,
        DateTimeOffset? to,
        AppDbContext db,
        CancellationToken ct)
    {
        var query = db.AuditLog
            .Include(e => e.Actor)
            .AsNoTracking();

        // Filters
        if (!string.IsNullOrWhiteSpace(actor))
        {
            var actorLower = actor.Trim().ToLowerInvariant();
            query = query.Where(e =>
                (e.Actor.DisplayName != null && e.Actor.DisplayName.ToLower().Contains(actorLower)) ||
                (e.Actor.Email != null && e.Actor.Email.ToLower().Contains(actorLower)));
        }

        if (!string.IsNullOrWhiteSpace(action))
            query = query.Where(e => e.Action.Contains(action.Trim()));

        if (from.HasValue)
            query = query.Where(e => e.CreatedAt >= from.Value);

        if (to.HasValue)
            query = query.Where(e => e.CreatedAt <= to.Value);

        var total = await query.CountAsync(ct);

        var items = await query
            .OrderByDescending(e => e.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
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
            page = pagination.NormalizedPage,
            page_size = pagination.Take
        });
    }
}
