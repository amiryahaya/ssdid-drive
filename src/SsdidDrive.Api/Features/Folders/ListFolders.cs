using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class ListFolders
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(Guid? parentId, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var tenantId = user.TenantId.Value;
        var now = DateTimeOffset.UtcNow;

        // Folder IDs shared with this user (active, non-expired shares).
        // Fetch candidates server-side, then filter expiry client-side for
        // cross-database compatibility (SQLite cannot compare DateTimeOffset).
        var sharedFolderIds = (await db.Shares
            .Where(s => s.SharedWithId == user.Id && s.ResourceType == "folder")
            .Select(s => new { s.ResourceId, s.ExpiresAt })
            .ToListAsync(ct))
            .Where(s => s.ExpiresAt == null || s.ExpiresAt > now)
            .Select(s => s.ResourceId)
            .ToList();

        var folders = await db.Folders
            .Where(f => f.TenantId == tenantId
                && f.ParentFolderId == parentId
                && (f.OwnerId == user.Id || sharedFolderIds.Contains(f.Id)))
            .Select(f => new
            {
                f.Id,
                f.Name,
                f.ParentFolderId,
                f.OwnerId,
                f.KemAlgorithm,
                f.CreatedAt,
                f.UpdatedAt,
                SubFolderCount = f.SubFolders.Count,
                FileCount = f.Files.Count
            })
            .OrderBy(f => f.Name)
            .ToListAsync(ct);

        return Results.Ok(folders);
    }
}
