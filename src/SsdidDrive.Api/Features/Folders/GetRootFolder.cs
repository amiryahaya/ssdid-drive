using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Folders;

public static class GetRootFolder
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/root", Handle);

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

        var folder = await db.Folders
            .Where(f => f.ParentFolderId == null && f.TenantId == tenantId)
            .FirstOrDefaultAsync(ct);

        if (folder is null)
        {
            // Auto-create root folder for tenant (new tenants from invitations won't have one)
            folder = new Folder
            {
                Name = "My Files",
                ParentFolderId = null,
                OwnerId = user.Id,
                TenantId = tenantId,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };

            db.Folders.Add(folder);
            await db.SaveChangesAsync(ct);
        }

        return Results.Ok(new
        {
            Data = FolderHelper.BuildFolderDto(folder)
        });
    }
}
