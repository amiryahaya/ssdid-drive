using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class UpdateTenant
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/tenants/{id:guid}", Handle);

    private record UpdateTenantRequest(string? Name, bool? Disabled, long? StorageQuotaBytes);

    private static async Task<IResult> Handle(
        Guid id,
        UpdateTenantRequest request,
        CurrentUserAccessor accessor,
        AppDbContext db,
        AuditService audit,
        CancellationToken ct)
    {
        var tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == id, ct);
        if (tenant is null)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        if (request.Name is not null)
        {
            if (string.IsNullOrWhiteSpace(request.Name))
                return AppError.BadRequest("Name cannot be empty").ToProblemResult();
            tenant.Name = request.Name.Trim();
        }

        if (request.Disabled is not null)
            tenant.Disabled = request.Disabled.Value;

        if (request.StorageQuotaBytes is not null)
            tenant.StorageQuotaBytes = request.StorageQuotaBytes.Value;

        tenant.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, request.Disabled == true ? "tenant.disabled" : "tenant.updated", "tenant", id, ct: ct);

        return Results.Ok(new
        {
            id = tenant.Id,
            name = tenant.Name,
            slug = tenant.Slug,
            disabled = tenant.Disabled,
            storage_quota_bytes = tenant.StorageQuotaBytes,
            created_at = tenant.CreatedAt,
            updated_at = tenant.UpdatedAt
        });
    }
}
