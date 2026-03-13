using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class SetupRecovery
{
    public record Request(string ServerShare, string KeyProof);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/setup", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        FileActivityService activity,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (string.IsNullOrWhiteSpace(req.ServerShare))
            return AppError.BadRequest("server_share is required").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyProof) || req.KeyProof.Length != 64)
            return AppError.BadRequest("key_proof must be a 64-character SHA-256 hex string").ToProblemResult();

        var existing = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id, ct);

        var isRegeneration = false;
        if (existing is not null)
        {
            isRegeneration = existing.IsActive;
            existing.ServerShare = req.ServerShare;
            existing.KeyProof = req.KeyProof;
            existing.ShareCreatedAt = DateTimeOffset.UtcNow;
            existing.IsActive = true;
        }
        else
        {
            db.RecoverySetups.Add(new RecoverySetup
            {
                UserId = user.Id,
                ServerShare = req.ServerShare,
                KeyProof = req.KeyProof,
                ShareCreatedAt = DateTimeOffset.UtcNow,
                IsActive = true
            });
        }

        user.HasRecoverySetup = true;
        await db.SaveChangesAsync(ct);

        var eventType = isRegeneration ? "recovery.regenerated" : "recovery.setup";
        _ = activity.LogAsync(
            user.Id, user.TenantId ?? Guid.Empty, eventType, "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.Created();
    }
}
