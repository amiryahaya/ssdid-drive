using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Activity;

public static class ListAdminActivity
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/admin", Handle);

    private static async Task<IResult> Handle(
        [AsParameters] PaginationParams pagination,
        Guid? actor_id,
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

        // Require Admin or Owner role in the tenant
        var membership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == user.Id && ut.TenantId == tenantId.Value, ct);

        if (membership is null || membership.Role == TenantRole.Member)
            return AppError.Forbidden("Admin or Owner role required").ToProblemResult();

        var query = db.FileActivities
            .Include(a => a.Actor)
            .Where(a => a.TenantId == tenantId.Value)
            .AsNoTracking();

        if (actor_id.HasValue)
            query = query.Where(a => a.ActorId == actor_id.Value);

        if (!string.IsNullOrWhiteSpace(event_type))
            query = query.Where(a => a.EventType == event_type);

        if (!string.IsNullOrWhiteSpace(resource_type))
            query = query.Where(a => a.ResourceType == resource_type);

        if (from.HasValue)
            query = query.Where(a => a.CreatedAt >= from.Value);

        if (to.HasValue)
            query = query.Where(a => a.CreatedAt <= to.Value);

        if (!string.IsNullOrWhiteSpace(pagination.Search))
        {
            var search = pagination.Search.ToLower();
            query = query.Where(a => a.ResourceName.ToLower().Contains(search));
        }

        var pageSize = Math.Clamp(pagination.PageSize, 1, 100);
        var page = Math.Max(1, pagination.Page);
        var total = await query.CountAsync(ct);

        // Client-side ordering for SQLite compatibility in tests
        var items = (await query
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
            .ToListAsync(ct))
            .OrderByDescending(a => a.created_at)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToList();

        return Results.Ok(new { items, total, page, page_size = pageSize });
    }
}
