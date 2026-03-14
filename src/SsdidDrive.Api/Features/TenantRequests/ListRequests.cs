using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class ListRequests
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenant-requests", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        string? status,
        CancellationToken ct)
    {
        var query = db.TenantRequests
            .Include(r => r.RequesterAccount)
            .AsQueryable();

        if (!string.IsNullOrEmpty(status) && Enum.TryParse<TenantRequestStatus>(status, true, out var statusFilter))
            query = query.Where(r => r.Status == statusFilter);
        else
            query = query.Where(r => r.Status == TenantRequestStatus.Pending);

        var requests = await query
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                id = r.Id,
                organization_name = r.OrganizationName,
                requester_email = r.RequesterEmail,
                requester_name = r.RequesterAccount != null ? r.RequesterAccount.DisplayName : null,
                reason = r.Reason,
                status = r.Status.ToString().ToLowerInvariant(),
                created_at = r.CreatedAt,
                reviewed_at = r.ReviewedAt,
                rejection_reason = r.RejectionReason
            })
            .ToListAsync(ct);

        return Results.Ok(new { items = requests });
    }
}
