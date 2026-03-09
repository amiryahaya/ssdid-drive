using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class SetShareExpiry
{
    public record Request(DateTimeOffset? ExpiresAt);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}/expiry", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (req.ExpiresAt.HasValue && req.ExpiresAt.Value <= DateTimeOffset.UtcNow)
            return AppError.BadRequest("Expiry date must be in the future").ToProblemResult();

        var share = await db.Shares.FirstOrDefaultAsync(s => s.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Share not found").ToProblemResult();

        if (share.SharedById != user.Id)
            return AppError.Forbidden("Only the share owner can update expiry").ToProblemResult();

        share.ExpiresAt = req.ExpiresAt;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            share.Id,
            share.ResourceId,
            share.ResourceType,
            share.SharedById,
            share.SharedWithId,
            share.Permission,
            share.ExpiresAt,
            share.CreatedAt
        });
    }
}
