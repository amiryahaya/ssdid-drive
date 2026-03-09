using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class SetupRecovery
{
    public record Request(int Threshold, int TotalShares);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/setup", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (req.Threshold < 2)
            return AppError.BadRequest("Threshold must be at least 2").ToProblemResult();

        if (req.TotalShares < req.Threshold)
            return AppError.BadRequest("Total shares must be >= threshold").ToProblemResult();

        if (req.TotalShares > 10)
            return AppError.BadRequest("Total shares must be <= 10").ToProblemResult();

        // Deactivate any existing active config for this user
        var existingConfigs = await db.RecoveryConfigs
            .Where(rc => rc.UserId == user.Id && rc.IsActive)
            .ToListAsync(ct);

        foreach (var existing in existingConfigs)
            existing.IsActive = false;

        // Cancel any pending recovery requests for deactivated configs
        var pendingRequests = await db.RecoveryRequests
            .Where(rr => existingConfigs.Select(c => c.Id).Contains(rr.RecoveryConfigId)
                && rr.Status == RecoveryRequestStatus.Pending)
            .ToListAsync(ct);
        foreach (var pr in pendingRequests)
            pr.Status = RecoveryRequestStatus.Rejected;

        var config = new RecoveryConfig
        {
            UserId = user.Id,
            Threshold = req.Threshold,
            TotalShares = req.TotalShares,
            IsActive = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.RecoveryConfigs.Add(config);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/recovery/status", new
        {
            config.Id,
            config.UserId,
            config.Threshold,
            config.TotalShares,
            config.IsActive,
            config.CreatedAt
        });
    }
}
