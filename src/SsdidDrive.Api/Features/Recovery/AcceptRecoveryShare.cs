using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class AcceptRecoveryShare
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/shares/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var share = await db.RecoveryShares
            .FirstOrDefaultAsync(rs => rs.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Recovery share not found").ToProblemResult();

        if (share.TrusteeId != user.Id)
            return AppError.Forbidden("Only the trustee can accept this share").ToProblemResult();

        if (share.Status != RecoveryShareStatus.Pending)
            return AppError.BadRequest("Share is not in pending status").ToProblemResult();

        share.Status = RecoveryShareStatus.Accepted;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            share.Id,
            Status = share.Status.ToString().ToLowerInvariant()
        });
    }
}
