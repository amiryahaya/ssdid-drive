using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListTenants
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenants", Handle);

    private static async Task<IResult> Handle(
        [AsParameters] PaginationParams pagination,
        AppDbContext db,
        CancellationToken ct)
    {
        var query = db.Tenants.AsQueryable();

        if (!string.IsNullOrWhiteSpace(pagination.Search))
        {
            var search = pagination.Search.ToLower();
            query = query.Where(t =>
                t.Name.ToLower().Contains(search) ||
                t.Slug.ToLower().Contains(search));
        }

        var total = await query.CountAsync(ct);

        var tenants = await query
            .OrderBy(t => t.Name)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .Select(t => new
            {
                id = t.Id,
                name = t.Name,
                slug = t.Slug,
                disabled = t.Disabled,
                storage_quota_bytes = t.StorageQuotaBytes,
                created_at = t.CreatedAt,
                user_count = t.UserTenants.Count
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            items = tenants,
            total,
            page = pagination.NormalizedPage,
            page_size = pagination.Take
        });
    }
}
