using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class CompleteRecovery
{
    public record Request(string OldDid, string NewDid, string KeyProof, string KemPublicKey);

    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapPost("/api/recovery/complete", Handle)
            .RequireRateLimiting("recovery-complete");

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

        var hasApprovedRequest = await db.RecoveryRequests
            .AnyAsync(rr => rr.RequesterId == user.Id
                && rr.Status == RecoveryRequestStatus.Approved
                && rr.ExpiresAt > DateTimeOffset.UtcNow, ct);
        if (!hasApprovedRequest)
            return AppError.Forbidden("No approved recovery request found").ToProblemResult();

        var expectedBytes = System.Text.Encoding.UTF8.GetBytes(setup.KeyProof);
        var actualBytes = System.Text.Encoding.UTF8.GetBytes(req.KeyProof);
        if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(expectedBytes, actualBytes))
            return AppError.Forbidden("Invalid key proof").ToProblemResult();

        // Validate base64 KEM public key
        byte[] kemKey;
        try
        {
            kemKey = Convert.FromBase64String(req.KemPublicKey);
        }
        catch (FormatException)
        {
            return AppError.BadRequest("kem_public_key must be valid base64").ToProblemResult();
        }

        // Atomic DID migration
        user.Did = req.NewDid;
        user.KemPublicKey = kemKey;
        user.HasRecoverySetup = false;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        // Invalidate recovery
        setup.IsActive = false;
        setup.ServerShare = "";

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        var approvedRequest = await db.RecoveryRequests
            .FirstOrDefaultAsync(rr => rr.RequesterId == user.Id && rr.Status == RecoveryRequestStatus.Approved, ct);
        if (approvedRequest is not null)
        {
            approvedRequest.Status = RecoveryRequestStatus.Completed;
            await db.SaveChangesAsync(ct);
        }

        // Invalidate all old sessions for the old DID
        sessionStore.InvalidateSessionsForDid(req.OldDid);

        // Create new session for the recovered DID
        var token = sessionStore.CreateSession(req.NewDid);
        if (token is null)
            return AppError.ServiceUnavailable("Session store is at capacity; try again shortly").ToProblemResult();

        _ = activity.LogAsync(
            user.Id, user.TenantId ?? Guid.Empty, "recovery.completed", "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.Ok(new
        {
            session_token = token,
            user_id = user.Id
        });
    }
}
