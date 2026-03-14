using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Folders;

public static class GetRootFolderContents
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/root/contents", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
        {
            // Auto-create a personal tenant for users without one (e.g. superadmins)
            var tenant = new Tenant
            {
                Id = Guid.NewGuid(),
                Name = "Personal",
                Slug = $"personal-{Guid.NewGuid():N}"
            };
            db.Tenants.Add(tenant);

            user.TenantId = tenant.Id;

            db.UserTenants.Add(new UserTenant
            {
                UserId = user.Id,
                TenantId = tenant.Id,
                Role = TenantRole.Owner,
                CreatedAt = DateTimeOffset.UtcNow
            });

            await db.SaveChangesAsync(ct);
        }

        var tenantId = user.TenantId.Value;

        // Find or create root folder
        var rootFolder = await db.Folders
            .Where(f => f.ParentFolderId == null && f.TenantId == tenantId)
            .FirstOrDefaultAsync(ct);

        if (rootFolder is null)
        {
            rootFolder = new Folder
            {
                Name = "My Files",
                ParentFolderId = null,
                OwnerId = user.Id,
                TenantId = tenantId,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };

            db.Folders.Add(rootFolder);
            await db.SaveChangesAsync(ct);
        }

        var now = DateTimeOffset.UtcNow;

        // Get shared folder IDs for this user
        var sharedFolderIds = (await db.Shares
            .Where(s => s.SharedWithId == user.Id && s.ResourceType == "folder" && s.RevokedAt == null)
            .Select(s => new { s.ResourceId, s.ExpiresAt })
            .ToListAsync(ct))
            .Where(s => s.ExpiresAt == null || s.ExpiresAt > now)
            .Select(s => s.ResourceId)
            .ToList();

        // Get subfolders
        var subfolders = await db.Folders
            .Where(f => f.ParentFolderId == rootFolder.Id && f.TenantId == tenantId
                && (f.OwnerId == user.Id || sharedFolderIds.Contains(f.Id)))
            .Select(f => new
            {
                f.Id,
                f.Name,
                ParentId = f.ParentFolderId,
                f.OwnerId,
                EncryptedFolderKey = f.EncryptedFolderKey != null
                    ? Convert.ToBase64String(f.EncryptedFolderKey)
                    : null,
                f.KemAlgorithm,
                f.CreatedAt,
                f.UpdatedAt
            })
            .OrderBy(f => f.Name)
            .ToListAsync(ct);

        // Get shared file IDs for this user
        var sharedFileIds = (await db.Shares
            .Where(s => s.SharedWithId == user.Id && s.ResourceType == "file" && s.RevokedAt == null)
            .Select(s => new { s.ResourceId, s.ExpiresAt })
            .ToListAsync(ct))
            .Where(s => s.ExpiresAt == null || s.ExpiresAt > now)
            .Select(s => s.ResourceId)
            .ToList();

        // Get files in root folder
        var files = await db.Files
            .Where(f => f.FolderId == rootFolder.Id
                && (f.UploadedById == user.Id || sharedFileIds.Contains(f.Id)))
            .Select(f => new
            {
                f.Id,
                f.Name,
                MimeType = f.ContentType,
                f.Size,
                FolderId = f.FolderId,
                OwnerId = f.UploadedById,
                EncryptedKey = f.EncryptedFileKey != null
                    ? Convert.ToBase64String(f.EncryptedFileKey)
                    : null,
                f.CreatedAt,
                f.UpdatedAt
            })
            .OrderBy(f => f.Name)
            .ToListAsync(ct);

        return Results.Ok(new
        {
            Folder = new
            {
                rootFolder.Id,
                rootFolder.Name,
                ParentId = rootFolder.ParentFolderId,
                rootFolder.OwnerId,
                EncryptedFolderKey = rootFolder.EncryptedFolderKey is not null
                    ? Convert.ToBase64String(rootFolder.EncryptedFolderKey)
                    : null,
                rootFolder.KemAlgorithm,
                rootFolder.CreatedAt,
                rootFolder.UpdatedAt
            },
            Files = files,
            Subfolders = subfolders
        });
    }
}
