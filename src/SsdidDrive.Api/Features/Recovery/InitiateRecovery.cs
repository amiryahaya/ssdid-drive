using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class InitiateRecovery
{
    public record Request(Guid RecoveryConfigId);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/requests", Handle);

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
            return AppError.Forbidden("Only the account owner can initiate recovery").ToProblemResult();

        // Check for existing pending request
        var existingPending = await db.RecoveryRequests
            .AnyAsync(rr => rr.RecoveryConfigId == config.Id && rr.Status == RecoveryRequestStatus.Pending, ct);

        if (existingPending)
            return AppError.Conflict("A pending recovery request already exists for this config").ToProblemResult();

        var request = new RecoveryRequest
        {
            RequesterId = user.Id,
            RecoveryConfigId = config.Id,
            Status = RecoveryRequestStatus.Pending,
            ApprovalsReceived = 0,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.RecoveryRequests.Add(request);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/recovery/requests/{request.Id}", new
        {
            request.Id,
            request.RequesterId,
            request.RecoveryConfigId,
            Status = request.Status.ToString().ToLowerInvariant(),
            request.ApprovalsReceived,
            request.CreatedAt
        });
    }
}
