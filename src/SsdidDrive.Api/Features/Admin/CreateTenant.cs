using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Admin;

public static class CreateTenant
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenants", Handle);

    private record CreateTenantRequest(string? Name, string? Slug);

    private static async Task<IResult> Handle(
        CreateTenantRequest request,
        AppDbContext db,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return AppError.BadRequest("Name is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(request.Slug))
            return AppError.BadRequest("Slug is required").ToProblemResult();

        var slugExists = await db.Tenants
            .AnyAsync(t => t.Slug.ToLower() == request.Slug.ToLower(), ct);

        if (slugExists)
            return AppError.Conflict($"A tenant with slug '{request.Slug}' already exists").ToProblemResult();

        var tenant = new Tenant
        {
            Name = request.Name.Trim(),
            Slug = request.Slug.Trim().ToLower(),
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        db.Tenants.Add(tenant);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/admin/tenants/{tenant.Id}", new
        {
            id = tenant.Id,
            name = tenant.Name,
            slug = tenant.Slug,
            disabled = tenant.Disabled,
            storage_quota_bytes = tenant.StorageQuotaBytes,
            user_count = 0,
            created_at = tenant.CreatedAt
        });
    }
}
