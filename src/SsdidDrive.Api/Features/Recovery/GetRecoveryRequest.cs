using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/requests/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var request = await db.RecoveryRequests
            .Include(rr => rr.Config)
            .FirstOrDefaultAsync(rr => rr.Id == id, ct);

        if (request is null)
            return AppError.NotFound("Recovery request not found").ToProblemResult();

        // Authorization: only the requester or the config owner may view this request
        if (request.RequesterId != user.Id && request.Config.UserId != user.Id)
            return AppError.NotFound("Recovery request not found").ToProblemResult();

        return Results.Ok(new
        {
            request.Id,
            request.RequesterId,
            request.RecoveryConfigId,
            Status = request.Status.ToString().ToLowerInvariant(),
            request.ApprovalsReceived,
            Threshold = request.Config.Threshold,
            request.CreatedAt,
            request.CompletedAt
        });
    }
}
