using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetPendingRequests
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/requests/pending", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        // Find recovery setups where current user is a trustee
        var trusteeSetupIds = await db.RecoveryTrustees
            .Where(rt => rt.TrusteeUserId == user.Id)
            .Select(rt => rt.RecoverySetupId)
            .ToListAsync(ct);

        if (trusteeSetupIds.Count == 0)
            return Results.Ok(new { requests = Array.Empty<object>() });

        var now = DateTimeOffset.UtcNow;
        // Find pending requests for those setups where this user hasn't decided yet
        var requests = await db.RecoveryRequests
            .Where(rr => trusteeSetupIds.Contains(rr.RecoverySetupId)
                && rr.Status == RecoveryRequestStatus.Pending
                && rr.ExpiresAt > now
                && !rr.Approvals.Any(a => a.TrusteeUserId == user.Id))
            .Select(rr => new
            {
                id = rr.Id,
                requester_name = rr.Requester.DisplayName,
                requester_email = rr.Requester.Email,
                status = rr.Status.ToString().ToLowerInvariant(),
                approved_count = rr.ApprovedCount,
                required_count = rr.RequiredCount,
                expires_at = rr.ExpiresAt,
                created_at = rr.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new { requests });
    }
}
