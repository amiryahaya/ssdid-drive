using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RevokeService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
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

        db.ExtensionServices.Remove(service);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.revoked", "ExtensionService", service.Id,
            $"Revoked extension service '{service.Name}'", ct);

        return Results.NoContent();
    }
}
