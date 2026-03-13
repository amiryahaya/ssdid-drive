using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryShare
{
    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapGet("/api/recovery/share", Handle)
            .RequireRateLimiting("recovery-share");

    private static async Task<IResult> Handle(
        string did,
        AppDbContext db,
        FileActivityService activity,
        CancellationToken ct)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();

        var setup = await db.RecoverySetups
            .Where(rs => rs.User.Did == did && rs.IsActive)
            .Select(rs => new
            {
                rs.ServerShare,
                UserId = rs.User.Id,
                rs.User.TenantId
            })
            .FirstOrDefaultAsync(ct);

        // Constant-time response: pad to minimum 200ms
        var elapsed = sw.ElapsedMilliseconds;
        if (elapsed < 200)
            await Task.Delay((int)(200 - elapsed), CancellationToken.None);

        if (setup is null)
        {
            _ = activity.LogAsync(
                Guid.Empty, Guid.Empty, "recovery.share_retrieved", "recovery",
                Guid.Empty, did, Guid.Empty,
                new { success = false, did }, ct: ct);
            return AppError.NotFound("No active recovery setup found").ToProblemResult();
        }

        _ = activity.LogAsync(
            setup.UserId, setup.TenantId ?? Guid.Empty, "recovery.share_retrieved", "recovery",
            setup.UserId, "recovery-share", setup.UserId,
            new { success = true }, ct: ct);

        return Results.Ok(new
        {
            server_share = setup.ServerShare,
            share_index = 3
        });
    }
}
