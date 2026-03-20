using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

/// <summary>
/// POST /api/recovery/requests/initiate
/// Authenticated endpoint: creates a recovery request for the current (logged-in) user.
/// Used from the settings screen when the user wants to initiate trustee-based recovery.
/// </summary>
public static class InitiateRecoveryRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/requests/initiate", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        NotificationService notifications,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var setup = await db.RecoverySetups
            .Include(rs => rs.Trustees)
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id && rs.IsActive, ct);

        if (setup is null || setup.Trustees.Count == 0)
            return AppError.NotFound("No active trustee recovery setup found. Set up trustees first.").ToProblemResult();

        // Check for existing pending request to avoid duplicates
        var existingPending = await db.RecoveryRequests
            .AnyAsync(rr => rr.RequesterId == user.Id
                && rr.Status == RecoveryRequestStatus.Pending
                && rr.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (existingPending)
            return AppError.Conflict("A pending recovery request already exists").ToProblemResult();

        var request = new RecoveryRequest
        {
            RequesterId = user.Id,
            RecoverySetupId = setup.Id,
            Status = RecoveryRequestStatus.Pending,
            ApprovedCount = 0,
            RequiredCount = setup.Threshold,
            ExpiresAt = DateTimeOffset.UtcNow.AddHours(48),
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.RecoveryRequests.Add(request);

        // Notify each trustee
        foreach (var trustee in setup.Trustees)
        {
            await notifications.CreateAsync(
                trustee.TrusteeUserId,
                "recovery.request",
                "Recovery Request",
                $"{user.DisplayName ?? user.Did} is requesting account recovery and needs your approval.",
                actionType: "recovery_request",
                actionResourceId: request.Id.ToString(),
                ct: ct);
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            request_id = request.Id,
            status = "pending",
            required_count = request.RequiredCount,
            expires_at = request.ExpiresAt
        });
    }
}
