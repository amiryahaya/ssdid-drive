using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class GetFolderChildren
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}/children", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        // Verify parent folder exists and user has access
        var parent = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id && f.TenantId == user.TenantId, ct);

        if (parent is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        var now = DateTimeOffset.UtcNow;
        var sharedFolderIds = (await db.Shares
            .Where(s => s.SharedWithId == user.Id && s.ResourceType == "folder")
            .Select(s => new { s.ResourceId, s.ExpiresAt })
            .ToListAsync(ct))
            .Where(s => s.ExpiresAt == null || s.ExpiresAt > now)
            .Select(s => s.ResourceId)
            .ToList();

        var children = await db.Folders
            .Where(f => f.ParentFolderId == id && f.TenantId == user.TenantId
                && (f.OwnerId == user.Id || sharedFolderIds.Contains(f.Id)))
            .OrderBy(f => f.Name)
            .ToListAsync(ct);

        return Results.Ok(new
        {
            Data = children.Select(f => FolderHelper.BuildFolderDto(f)).ToList()
        });
    }
}
