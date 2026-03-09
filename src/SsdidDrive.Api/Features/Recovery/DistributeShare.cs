using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class DistributeShare
{
    public record Request(Guid RecoveryConfigId, Guid TrusteeId, string EncryptedShare);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/shares", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var config = await db.RecoveryConfigs
            .FirstOrDefaultAsync(rc => rc.Id == req.RecoveryConfigId && rc.IsActive, ct);

        if (config is null)
            return AppError.NotFound("Recovery config not found").ToProblemResult();

        if (config.UserId != user.Id)
            return AppError.Forbidden("Only the config owner can distribute shares").ToProblemResult();

        // Verify trustee exists
        var trustee = await db.Users.FirstOrDefaultAsync(u => u.Id == req.TrusteeId, ct);
        if (trustee is null)
            return AppError.NotFound("Trustee user not found").ToProblemResult();

        if (req.TrusteeId == user.Id)
            return AppError.BadRequest("Cannot distribute a share to yourself").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.EncryptedShare))
            return AppError.BadRequest("Encrypted share is required").ToProblemResult();

        // Check share count limit
        var existingCount = await db.RecoveryShares
            .CountAsync(rs => rs.RecoveryConfigId == config.Id, ct);

        if (existingCount >= config.TotalShares)
            return AppError.BadRequest("All shares have already been distributed").ToProblemResult();

        // Check duplicate trustee
        var alreadyDistributed = await db.RecoveryShares
            .AnyAsync(rs => rs.RecoveryConfigId == config.Id && rs.TrusteeId == req.TrusteeId, ct);

        if (alreadyDistributed)
            return AppError.Conflict("A share has already been distributed to this trustee").ToProblemResult();

        var share = new RecoveryShare
        {
            RecoveryConfigId = config.Id,
            TrusteeId = req.TrusteeId,
            EncryptedShare = Convert.FromBase64String(req.EncryptedShare),
            Status = RecoveryShareStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.RecoveryShares.Add(share);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/recovery/shares/{share.Id}", new
        {
            share.Id,
            share.RecoveryConfigId,
            share.TrusteeId,
            EncryptedShare = Convert.ToBase64String(share.EncryptedShare),
            Status = share.Status.ToString(),
            share.CreatedAt
        });
    }
}
