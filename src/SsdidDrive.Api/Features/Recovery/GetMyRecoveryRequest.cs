using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

/// <summary>
/// GET /api/recovery/requests/mine
/// Authenticated endpoint: returns the current user's most recent active recovery request, if any.
/// Used by InitiateRecoveryViewModel.checkRecoveryStatus().
/// </summary>
public static class GetMyRecoveryRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/requests/mine", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var now = DateTimeOffset.UtcNow;
        // Return the most recent pending or approved request (within expiry)
        var request = await db.RecoveryRequests
            .Where(rr => rr.RequesterId == user.Id
                && rr.ExpiresAt > now
                && (rr.Status == RecoveryRequestStatus.Pending || rr.Status == RecoveryRequestStatus.Approved))
            .OrderByDescending(rr => rr.CreatedAt)
            .Select(rr => new
            {
                id = rr.Id,
                status = rr.Status.ToString().ToLowerInvariant(),
                approved_shares = rr.ApprovedCount,
                required_shares = rr.RequiredCount,
                expires_at = rr.ExpiresAt,
                created_at = rr.CreatedAt
            })
            .FirstOrDefaultAsync(ct);

        return Results.Ok(new { request });
    }
}
