using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryStatus
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/status", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var config = await db.RecoveryConfigs
            .Where(rc => rc.UserId == user.Id && rc.IsActive)
            .Select(rc => new
            {
                rc.Id,
                rc.UserId,
                rc.Threshold,
                rc.TotalShares,
                rc.IsActive,
                rc.CreatedAt,
                Shares = rc.Shares.Select(s => new
                {
                    s.Id,
                    s.TrusteeId,
                    TrusteeDisplayName = s.Trustee.DisplayName,
                    Status = s.Status.ToString().ToLowerInvariant(),
                    s.CreatedAt
                }).ToList()
            })
            .FirstOrDefaultAsync(ct);

        if (config is null)
            return AppError.NotFound("No active recovery config found").ToProblemResult();

        return Results.Ok(config);
    }
}
