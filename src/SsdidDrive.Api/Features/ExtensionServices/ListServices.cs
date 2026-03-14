using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class ListServices
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var services = await db.ExtensionServices
            .Where(s => s.TenantId == tenantId)
            .OrderBy(s => s.Name)
            .Select(s => new
            {
                id = s.Id,
                name = s.Name,
                permissions = s.Permissions,
                enabled = s.Enabled,
                created_at = s.CreatedAt,
                last_used_at = s.LastUsedAt
            })
            .ToListAsync(ct);

        var items = services.Select(s => new
        {
            s.id,
            s.name,
            permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(s.permissions),
            s.enabled,
            s.created_at,
            s.last_used_at
        });

        return Results.Ok(new { items });
    }
}
