using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class RejectRecoveryRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/requests/{id:guid}/reject", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var request = await db.RecoveryRequests
            .Include(rr => rr.Approvals)
            .FirstOrDefaultAsync(rr => rr.Id == id, ct);
        if (request is null)
            return AppError.NotFound("Recovery request not found").ToProblemResult();

        if (request.Status != RecoveryRequestStatus.Pending)
            return AppError.BadRequest("Recovery request is no longer pending").ToProblemResult();
        if (request.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            request.Status = RecoveryRequestStatus.Expired;
            await db.SaveChangesAsync(ct);
            return AppError.Gone("Recovery request has expired").ToProblemResult();
        }

        // Validate user is a trustee for this request's setup
        var isTrustee = await db.RecoveryTrustees
            .AnyAsync(rt => rt.RecoverySetupId == request.RecoverySetupId
                && rt.TrusteeUserId == user.Id, ct);
        if (!isTrustee)
            return AppError.Forbidden("You are not a trustee for this recovery request").ToProblemResult();

        // Check for existing decision
        var alreadyDecided = request.Approvals.Any(a => a.TrusteeUserId == user.Id);
        if (alreadyDecided)
            return AppError.Conflict("You have already responded to this request").ToProblemResult();

        // Create rejection
        db.RecoveryRequestApprovals.Add(new RecoveryRequestApproval
        {
            RecoveryRequestId = request.Id,
            TrusteeUserId = user.Id,
            Decision = ApprovalDecision.Rejected,
            DecidedAt = DateTimeOffset.UtcNow
        });

        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            request_id = request.Id,
            status = request.Status.ToString().ToLowerInvariant(),
            decision = "rejected"
        });
    }
}
