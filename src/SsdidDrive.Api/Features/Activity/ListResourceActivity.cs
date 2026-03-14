using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Activity;

public static class ListResourceActivity
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/resource/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        [AsParameters] PaginationParams pagination,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var tenantId = user.TenantId;

        if (tenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        // Verify user has access: is file owner, folder owner, or has active share
        var isFileOwner = await db.Files
            .AnyAsync(f => f.Id == id && f.UploadedById == user.Id && f.Folder.TenantId == tenantId, ct);

        var isFolderOwner = !isFileOwner && await db.Folders
            .AnyAsync(f => f.Id == id && f.OwnerId == user.Id && f.TenantId == tenantId, ct);

        var hasShare = !isFileOwner && !isFolderOwner && await db.Shares
            .AnyAsync(s => s.ResourceId == id && s.SharedWithId == user.Id && s.RevokedAt == null
                && (db.Files.Any(f => f.Id == id && f.Folder.TenantId == tenantId)
                    || db.Folders.Any(f => f.Id == id && f.TenantId == tenantId)), ct);

        if (!isFileOwner && !isFolderOwner && !hasShare)
            return AppError.NotFound("Resource not found or access denied").ToProblemResult();

        var pageSize = Math.Clamp(pagination.PageSize, 1, 50);
        var page = Math.Max(1, pagination.Page);

        var query = db.FileActivities
            .Include(a => a.Actor)
            .Where(a => a.ResourceId == id && a.TenantId == tenantId.Value)
            .AsNoTracking();

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
