using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Shares;

public static class UpdateSharePermission
{
    public record Request(string Permission);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}/permission", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (req.Permission is not ("read" or "write"))
            return AppError.BadRequest("Permission must be 'read' or 'write'").ToProblemResult();

        var share = await db.Shares.FirstOrDefaultAsync(s => s.Id == id, ct);

        if (share is null)
            return AppError.NotFound("Share not found").ToProblemResult();

        if (share.SharedById != user.Id)
            return AppError.Forbidden("Only the share owner can update permission").ToProblemResult();

        share.Permission = req.Permission;
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
