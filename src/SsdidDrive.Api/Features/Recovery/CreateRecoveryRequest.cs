using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class CreateRecoveryRequest
{
    public record Request(string Did);

    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapPost("/api/recovery/requests", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("recovery-create")
            .WithTags("Recovery");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        NotificationService notifications,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Did))
            return AppError.BadRequest("did is required").ToProblemResult();

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Did == req.Did, ct);

        var setup = user is null ? null : await db.RecoverySetups
            .Include(rs => rs.Trustees)
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id && rs.IsActive, ct);

        if (user is null || setup is null || setup.Trustees.Count == 0)
            return AppError.NotFound("No active recovery setup found for this DID").ToProblemResult();

        // Check for existing pending request
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
