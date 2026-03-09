using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListUsers
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/users", Handle);

    private static async Task<IResult> Handle(
        [AsParameters] PaginationParams pagination,
        AppDbContext db,
        CancellationToken ct)
    {
        var query = db.Users.AsQueryable();

        if (!string.IsNullOrWhiteSpace(pagination.Search))
        {
            var search = pagination.Search.ToLower();
            query = query.Where(u =>
                (u.DisplayName != null && u.DisplayName.ToLower().Contains(search)) ||
                u.Did.ToLower().Contains(search) ||
                (u.Email != null && u.Email.ToLower().Contains(search)));
        }

        var total = await query.CountAsync(ct);

        var users = await query
            .OrderBy(u => u.Id)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .ToListAsync(ct);

        var items = users.Select(u => new
        {
            id = u.Id,
            did = u.Did,
            display_name = u.DisplayName,
            email = u.Email,
            status = u.Status.ToString().ToLower(),
            system_role = u.SystemRole?.ToString(),
            tenant_id = u.TenantId,
            last_login_at = u.LastLoginAt,
            created_at = u.CreatedAt
        });

        return Results.Ok(new
        {
            items,
            total,
            page = pagination.NormalizedPage,
            page_size = pagination.Take
        });
    }
}
