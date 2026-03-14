using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RegisterService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private record RegisterRequest(string? Name, Dictionary<string, bool>? Permissions);

    private static async Task<IResult> Handle(
        RegisterRequest request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        TotpEncryption encryption,
        AuditService audit,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return AppError.BadRequest("Name is required").ToProblemResult();

        var tenantId = accessor.User!.TenantId!.Value;

        var exists = await db.ExtensionServices
            .AnyAsync(s => s.TenantId == tenantId && s.Name == request.Name.Trim(), ct);
        if (exists)
            return AppError.Conflict($"A service named '{request.Name}' already exists in this tenant").ToProblemResult();

        var secretBytes = RandomNumberGenerator.GetBytes(32);
        var secretBase64 = Convert.ToBase64String(secretBytes);
        var encryptedSecret = encryption.Encrypt(secretBase64);

        var permissions = request.Permissions ?? new Dictionary<string, bool>();
        var permissionsJson = JsonSerializer.Serialize(permissions);

        var service = new ExtensionService
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = request.Name.Trim(),
            ServiceKey = encryptedSecret,
            Permissions = permissionsJson,
            Enabled = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.ExtensionServices.Add(service);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.registered", "ExtensionService", service.Id,
            $"Registered extension service '{service.Name}'", ct);

        return Results.Created($"/api/tenant/services/{service.Id}", new
        {
            id = service.Id,
            name = service.Name,
            service_key = secretBase64,
            permissions,
            enabled = service.Enabled,
            created_at = service.CreatedAt
        });
    }
}
