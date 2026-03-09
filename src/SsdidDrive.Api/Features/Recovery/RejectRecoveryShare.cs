using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Recovery;

public static class RejectRecoveryShare
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/shares/{id:guid}/reject", Handle);

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
            return AppError.Forbidden("Only the trustee can reject this share").ToProblemResult();

        if (share.Status != RecoveryShareStatus.Pending)
            return AppError.BadRequest("Share is not in pending status").ToProblemResult();

        share.Status = RecoveryShareStatus.Rejected;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            share.Id,
            Status = share.Status.ToString().ToLowerInvariant()
        });
    }
}
