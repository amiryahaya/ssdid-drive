using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RotateSecret
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/rotate", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        TotpEncryption encryption,
        AuditService audit,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        var newSecretBytes = RandomNumberGenerator.GetBytes(32);
        var newSecretBase64 = Convert.ToBase64String(newSecretBytes);

        service.ServiceKey = encryption.Encrypt(newSecretBase64);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.secret.rotated", "ExtensionService", service.Id,
            $"Rotated HMAC secret for service '{service.Name}'", ct);

        return Results.Ok(new
        {
            id = service.Id,
            name = service.Name,
            service_key = newSecretBase64
        });
    }
}
