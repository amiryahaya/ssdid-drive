using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static partial class ApproveRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenant-requests/{id:guid}/approve", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        var request = await db.TenantRequests.FindAsync([id], ct);
        if (request is null)
            return AppError.NotFound("Tenant request not found").ToProblemResult();

        if (request.Status != TenantRequestStatus.Pending)
            return AppError.Conflict($"Request is already {request.Status.ToString().ToLowerInvariant()}").ToProblemResult();

        var slug = SlugRegex().Replace(request.OrganizationName.ToLowerInvariant(), "-").Trim('-');
        if (string.IsNullOrEmpty(slug)) slug = $"org-{Guid.NewGuid():N}"[..16];

        var baseSlug = slug;
        var counter = 1;
        while (await db.Tenants.AnyAsync(t => t.Slug == slug, ct))
        {
            slug = $"{baseSlug}-{counter}";
            counter++;
        }

        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = request.OrganizationName,
            Slug = slug,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);

        if (request.RequesterAccountId.HasValue)
        {
            db.UserTenants.Add(new UserTenant
            {
                UserId = request.RequesterAccountId.Value,
                TenantId = tenant.Id,
                Role = TenantRole.Owner,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        request.Status = TenantRequestStatus.Approved;
        request.ReviewedBy = accessor.UserId;
        request.ReviewedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.request.approved", "TenantRequest", request.Id,
            $"Approved tenant request for '{request.OrganizationName}', created tenant {tenant.Id}", ct);

        return Results.Ok(new
        {
            id = request.Id,
            organization_name = request.OrganizationName,
            status = "approved",
            tenant_id = tenant.Id,
            tenant_slug = tenant.Slug,
            reviewed_at = request.ReviewedAt
        });
    }

    [GeneratedRegex(@"[^a-z0-9]+")]
    private static partial Regex SlugRegex();
}
