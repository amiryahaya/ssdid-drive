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
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

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
            Data = BuildResponse(folder)
        });
    }

    private static object BuildResponse(Folder f) => new
    {
        f.Id,
        f.Name,
        ParentId = f.ParentFolderId,
        f.OwnerId,
        f.TenantId,
        IsRoot = true,
        EncryptedMetadata = (string?)null,
        MetadataNonce = (string?)null,
        WrappedKek = f.EncryptedFolderKey is not null ? Convert.ToBase64String(f.EncryptedFolderKey) : "",
        KemCiphertext = (string?)null,
        OwnerWrappedKek = f.EncryptedFolderKey is not null ? Convert.ToBase64String(f.EncryptedFolderKey) : "",
        OwnerKemCiphertext = "",
        Signature = (string?)null,
        f.KemAlgorithm,
        f.CreatedAt,
        f.UpdatedAt,
        SubFolderCount = 0,
        FileCount = 0
    };
}
