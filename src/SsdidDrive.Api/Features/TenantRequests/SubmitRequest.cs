using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class SubmitRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private record SubmitRequestBody(string? OrganizationName, string? Reason);

    private static async Task<IResult> Handle(
        SubmitRequestBody request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.OrganizationName))
            return AppError.BadRequest("Organization name is required").ToProblemResult();

        var alreadyPending = await db.TenantRequests
            .AnyAsync(r => r.RequesterAccountId == accessor.UserId
                           && r.Status == TenantRequestStatus.Pending, ct);
        if (alreadyPending)
            return AppError.Conflict("You already have a pending tenant request").ToProblemResult();

        var tenantRequest = new TenantRequest
        {
            Id = Guid.NewGuid(),
            OrganizationName = request.OrganizationName.Trim(),
            RequesterEmail = accessor.User!.Email ?? "",
            RequesterAccountId = accessor.UserId,
            Reason = request.Reason?.Trim(),
            Status = TenantRequestStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.TenantRequests.Add(tenantRequest);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.requested", "TenantRequest", tenantRequest.Id,
            $"Requested tenant creation: '{tenantRequest.OrganizationName}'", ct);

        return Results.Created($"/api/tenant-requests/{tenantRequest.Id}", new
        {
            id = tenantRequest.Id,
            organization_name = tenantRequest.OrganizationName,
            reason = tenantRequest.Reason,
            status = "pending",
            created_at = tenantRequest.CreatedAt
        });
    }
}
