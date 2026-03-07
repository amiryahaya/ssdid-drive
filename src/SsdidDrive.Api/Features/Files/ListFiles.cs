using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Files;

public static class ListFiles
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/folders/{folderId:guid}/files", Handle);

    private static async Task<IResult> Handle(Guid folderId, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == folderId && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Check ownership or share access.
        // Evaluate expiry client-side for cross-database compatibility
        // (SQLite cannot compare DateTimeOffset in LINQ).
        var now = DateTimeOffset.UtcNow;
        var hasAccess = folder.OwnerId == user.Id
            || (await db.Shares
                .Where(s => s.ResourceId == folderId && s.ResourceType == "folder" && s.SharedWithId == user.Id)
                .Select(s => s.ExpiresAt)
                .ToListAsync(ct))
                .Any(e => e == null || e > now);

        if (!hasAccess)
            return AppError.Forbidden("You do not have access to this folder").ToProblemResult();

        var files = await db.Files
            .Where(f => f.FolderId == folderId)
            .Select(f => new
            {
                f.Id,
                f.Name,
                f.ContentType,
                f.Size,
                f.FolderId,
                f.UploadedById,
                f.EncryptionAlgorithm,
                f.CreatedAt,
                f.UpdatedAt
            })
            .OrderBy(f => f.Name)
            .ToListAsync(ct);

        return Results.Ok(files);
    }
}
