using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class RejectRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenant-requests/{id:guid}/reject", Handle);

    private record RejectRequestBody(string? Reason);

    private static async Task<IResult> Handle(
        Guid id,
        RejectRequestBody request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        IEmailService emailService,
        CancellationToken ct)
    {
        var tenantRequest = await db.TenantRequests.FindAsync([id], ct);
        if (tenantRequest is null)
            return AppError.NotFound("Tenant request not found").ToProblemResult();

        if (tenantRequest.Status != TenantRequestStatus.Pending)
            return AppError.Conflict($"Request is already {tenantRequest.Status.ToString().ToLowerInvariant()}").ToProblemResult();

        tenantRequest.Status = TenantRequestStatus.Rejected;
        tenantRequest.RejectionReason = request.Reason?.Trim();
        tenantRequest.ReviewedBy = accessor.UserId;
        tenantRequest.ReviewedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.request.rejected", "TenantRequest", tenantRequest.Id,
            $"Rejected tenant request for '{tenantRequest.OrganizationName}': {request.Reason}", ct);

        if (!string.IsNullOrEmpty(tenantRequest.RequesterEmail))
        {
            try
            {
                await emailService.SendRejectionAsync(
                    tenantRequest.RequesterEmail,
                    tenantRequest.OrganizationName,
                    request.Reason,
                    ct);
            }
            catch { /* email failure should not block the rejection */ }
        }

        return Results.Ok(new
        {
            id = tenantRequest.Id,
            organization_name = tenantRequest.OrganizationName,
            status = "rejected",
            rejection_reason = tenantRequest.RejectionReason,
            reviewed_at = tenantRequest.ReviewedAt
        });
    }
}
