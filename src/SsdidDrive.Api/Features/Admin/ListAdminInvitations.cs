using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Admin;

public static class ListAdminInvitations
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenants/{tenantId:guid}/invitations", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, [AsParameters] PaginationParams pagination,
        AppDbContext db, string? status, CancellationToken ct)
    {
        var tenantExists = await db.Tenants.AnyAsync(t => t.Id == tenantId, ct);
        if (!tenantExists)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        var query = db.Invitations.Where(i => i.TenantId == tenantId);

        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<InvitationStatus>(status, ignoreCase: true, out var parsedStatus))
        {
            query = query.Where(i => i.Status == parsedStatus);
        }

        var ordered = query.OrderByDescending(i => i.CreatedAt);

        var total = await ordered.CountAsync(ct);

        var items = await ordered
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .Select(i => new
            {
                id = i.Id,
                tenant_id = i.TenantId,
                invited_by_id = i.InvitedById,
                email = i.Email,
                invited_user_id = i.InvitedUserId,
                role = i.Role.ToString().ToLowerInvariant(),
                status = i.Status.ToString().ToLowerInvariant(),
                short_code = i.ShortCode,
                message = i.Message,
                expires_at = i.ExpiresAt,
                created_at = i.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            items,
            total,
            page = pagination.NormalizedPage,
            page_size = pagination.Take
        });
    }
}
