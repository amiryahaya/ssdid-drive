using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Activity;

public static class ListActivity
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(
        [AsParameters] PaginationParams pagination,
        string? event_type,
        string? resource_type,
        DateTimeOffset? from,
        DateTimeOffset? to,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var tenantId = user.TenantId;

        if (tenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var query = db.FileActivities
            .Include(a => a.Actor)
            .Where(a => a.TenantId == tenantId.Value)
            .Where(a => a.ActorId == user.Id || a.ResourceOwnerId == user.Id)
            .AsNoTracking();

        if (!string.IsNullOrWhiteSpace(event_type))
            query = query.Where(a => a.EventType == event_type);

        if (!string.IsNullOrWhiteSpace(resource_type))
            query = query.Where(a => a.ResourceType == resource_type);

        if (from.HasValue)
            query = query.Where(a => a.CreatedAt >= from.Value);

        if (to.HasValue)
            query = query.Where(a => a.CreatedAt <= to.Value);

        var pageSize = Math.Clamp(pagination.PageSize, 1, 50);
        var page = Math.Max(1, pagination.Page);
        var total = await query.CountAsync(ct);

        var items = await query
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new
            {
                id = a.Id,
                actor_id = a.ActorId,
                actor_name = a.Actor.DisplayName,
                event_type = a.EventType,
                resource_type = a.ResourceType,
                resource_id = a.ResourceId,
                resource_name = a.ResourceName,
                details = a.Details,
                created_at = a.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new { items, total, page, page_size = pageSize });
    }
}
