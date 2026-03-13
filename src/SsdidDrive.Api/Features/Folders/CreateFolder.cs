using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Folders;

public static class CreateFolder
{
    private record Request(
        string? ParentId,
        string EncryptedMetadata,
        string MetadataNonce,
        string WrappedKek,
        string? KemCiphertext,
        string OwnerWrappedKek,
        string OwnerKemCiphertext,
        string? MlKemCiphertext,
        string? OwnerMlKemCiphertext,
        string Signature);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        Guid? parentId = null;
        if (!string.IsNullOrWhiteSpace(req.ParentId))
        {
            if (!Guid.TryParse(req.ParentId, out var pid))
                return AppError.BadRequest("Invalid parent ID").ToProblemResult();
            parentId = pid;

            var parent = await db.Folders
                .FirstOrDefaultAsync(f => f.Id == parentId && f.TenantId == user.TenantId, ct);
            if (parent is null)
                return AppError.NotFound("Parent folder not found").ToProblemResult();
        }

        var now = DateTimeOffset.UtcNow;
        var folder = new Folder
        {
            Name = "encrypted",
            ParentFolderId = parentId,
            OwnerId = user.Id,
            TenantId = user.TenantId.Value,
            EncryptedMetadata = req.EncryptedMetadata,
            MetadataNonce = req.MetadataNonce,
            WrappedKek = req.WrappedKek,
            KemCiphertext = req.KemCiphertext,
            OwnerWrappedKek = req.OwnerWrappedKek,
            OwnerKemCiphertext = req.OwnerKemCiphertext,
            MlKemCiphertext = req.MlKemCiphertext,
            OwnerMlKemCiphertext = req.OwnerMlKemCiphertext,
            Signature = req.Signature,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Folders.Add(folder);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/folders/{folder.Id}", new
        {
            Data = FolderHelper.BuildFolderDto(folder)
        });
    }
}
