using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetReleasedShares
{
    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapGet("/api/recovery/requests/{id:guid}/shares", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("recovery-share")
            .WithTags("Recovery");

    private static async Task<IResult> Handle(
        Guid id,
        string did,
        AppDbContext db,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(did))
            return AppError.BadRequest("did query parameter is required").ToProblemResult();

        var request = await db.RecoveryRequests
            .Include(rr => rr.Requester)
            .FirstOrDefaultAsync(rr => rr.Id == id, ct);
        if (request is null)
            return AppError.NotFound("Recovery request not found").ToProblemResult();

        // Verify the DID matches the requester
        if (request.Requester.Did != did)
            return AppError.Forbidden("DID does not match the recovery requester").ToProblemResult();

        if (request.Status != RecoveryRequestStatus.Approved)
            return AppError.BadRequest($"Recovery request is not approved (current status: {request.Status.ToString().ToLowerInvariant()})").ToProblemResult();

        if (request.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            request.Status = RecoveryRequestStatus.Expired;
            await db.SaveChangesAsync(ct);
            return AppError.Gone("Recovery request has expired").ToProblemResult();
        }

        // Get encrypted shares from trustees who approved
        var approvedTrusteeIds = await db.RecoveryRequestApprovals
            .Where(a => a.RecoveryRequestId == id && a.Decision == ApprovalDecision.Approved)
            .Select(a => a.TrusteeUserId)
            .ToListAsync(ct);

        var shares = await db.RecoveryTrustees
            .Where(rt => rt.RecoverySetupId == request.RecoverySetupId
                && approvedTrusteeIds.Contains(rt.TrusteeUserId))
            .Select(rt => new
            {
                trustee_user_id = rt.TrusteeUserId,
                encrypted_share = Convert.ToBase64String(rt.EncryptedShare),
                share_index = rt.ShareIndex
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            request_id = request.Id,
            status = request.Status.ToString().ToLowerInvariant(),
            shares
        });
    }
}
