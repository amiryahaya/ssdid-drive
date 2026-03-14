using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class GetService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        var permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions);

        return Results.Ok(new
        {
            id = service.Id,
            name = service.Name,
            permissions,
            enabled = service.Enabled,
            created_at = service.CreatedAt,
            last_used_at = service.LastUsedAt
        });
    }
}
