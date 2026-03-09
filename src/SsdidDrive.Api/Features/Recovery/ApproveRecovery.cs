using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class ApproveRecovery
{
    public record Request(string EncryptedShare);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/requests/{id:guid}/approve", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var recoveryRequest = await db.RecoveryRequests
            .Include(rr => rr.Config)
            .FirstOrDefaultAsync(rr => rr.Id == id, ct);

        if (recoveryRequest is null)
            return AppError.NotFound("Recovery request not found").ToProblemResult();

        if (recoveryRequest.Status != RecoveryRequestStatus.Pending)
            return AppError.BadRequest("Recovery request is not in pending status").ToProblemResult();

        // Verify the current user is a trustee with an accepted share for this config
        var trusteeShare = await db.RecoveryShares
            .FirstOrDefaultAsync(rs =>
                rs.RecoveryConfigId == recoveryRequest.RecoveryConfigId
                && rs.TrusteeId == user.Id
                && rs.Status == RecoveryShareStatus.Accepted, ct);

        if (trusteeShare is null)
            return AppError.Forbidden("You are not an accepted trustee for this recovery config").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.EncryptedShare))
            return AppError.BadRequest("Encrypted share is required").ToProblemResult();

        recoveryRequest.ApprovalsReceived++;

        if (recoveryRequest.ApprovalsReceived >= recoveryRequest.Config.Threshold)
        {
            recoveryRequest.Status = RecoveryRequestStatus.Approved;
            recoveryRequest.CompletedAt = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            recoveryRequest.Id,
            Status = recoveryRequest.Status.ToString(),
            recoveryRequest.ApprovalsReceived,
            Threshold = recoveryRequest.Config.Threshold,
            recoveryRequest.CompletedAt
        });
    }
}
