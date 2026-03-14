using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class UpdateService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/{id:guid}", Handle);

    private record UpdateRequest(Dictionary<string, bool>? Permissions, bool? Enabled);

    private static async Task<IResult> Handle(
        Guid id,
        UpdateRequest request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        if (request.Permissions is not null)
            service.Permissions = JsonSerializer.Serialize(request.Permissions);

        if (request.Enabled.HasValue)
            service.Enabled = request.Enabled.Value;

        await db.SaveChangesAsync(ct);

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
