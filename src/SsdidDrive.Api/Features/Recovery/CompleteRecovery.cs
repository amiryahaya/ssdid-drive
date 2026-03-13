using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class CompleteRecovery
{
    public record Request(string OldDid, string NewDid, string KeyProof, string KemPublicKey);

    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapPost("/api/recovery/complete", Handle)
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        ISessionStore sessionStore,
        FileActivityService activity,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.OldDid) || string.IsNullOrWhiteSpace(req.NewDid)
            || string.IsNullOrWhiteSpace(req.KeyProof) || string.IsNullOrWhiteSpace(req.KemPublicKey))
            return AppError.BadRequest("All fields are required").ToProblemResult();

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Did == req.OldDid, ct);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        var setup = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id && rs.IsActive, ct);
        if (setup is null)
            return AppError.NotFound("No active recovery setup found").ToProblemResult();

        if (!string.Equals(setup.KeyProof, req.KeyProof, StringComparison.OrdinalIgnoreCase))
            return AppError.Forbidden("Invalid key proof").ToProblemResult();

        // Atomic DID migration
        user.Did = req.NewDid;
        user.KemPublicKey = Convert.FromBase64String(req.KemPublicKey);
        user.HasRecoverySetup = false;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        // Invalidate recovery
        setup.IsActive = false;
        setup.ServerShare = "";

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        // Create new session for the recovered DID
        var token = sessionStore.CreateSession(req.NewDid);
        if (token is null)
            return AppError.ServiceUnavailable("Session store is at capacity; try again shortly").ToProblemResult();

        _ = activity.LogAsync(
            user.Id, user.TenantId ?? Guid.Empty, "recovery.completed", "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.Ok(new
        {
            token,
            user_id = user.Id
        });
    }
}
