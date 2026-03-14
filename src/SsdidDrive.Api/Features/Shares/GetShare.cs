using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class GetShare
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var share = await db.Shares
            .Include(s => s.SharedBy)
            .Include(s => s.SharedWith)
            .FirstOrDefaultAsync(s => s.Id == id && s.RevokedAt == null, ct);

        if (share is null || (share.SharedById != user.Id && share.SharedWithId != user.Id))
            return AppError.NotFound("Share not found").ToProblemResult();

        return Results.Ok(new
        {
            share.Id,
            share.ResourceId,
            share.ResourceType,
            share.SharedById,
            SharedByName = share.SharedBy.DisplayName ?? share.SharedBy.Did,
            share.SharedWithId,
            SharedWithName = share.SharedWith.DisplayName ?? share.SharedWith.Did,
            share.Permission,
            EncryptedKey = share.EncryptedKey is not null ? Convert.ToBase64String(share.EncryptedKey) : null,
            share.KemAlgorithm,
            share.ExpiresAt,
            share.CreatedAt
        });
    }
}
