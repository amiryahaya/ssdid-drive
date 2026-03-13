using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class UpdateFolder
{
    private record Request(
        string? EncryptedMetadata,
        string? MetadataNonce,
        string? WrappedKek,
        string? KemCiphertext,
        string? OwnerWrappedKek,
        string? OwnerKemCiphertext,
        string? MlKemCiphertext,
        string? OwnerMlKemCiphertext,
        string? Signature);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;
        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != user.Id)
            return AppError.Forbidden("Only the folder owner can update it").ToProblemResult();

        if (req.EncryptedMetadata is not null) folder.EncryptedMetadata = req.EncryptedMetadata;
        if (req.MetadataNonce is not null) folder.MetadataNonce = req.MetadataNonce;
        if (req.WrappedKek is not null) folder.WrappedKek = req.WrappedKek;
        if (req.KemCiphertext is not null) folder.KemCiphertext = req.KemCiphertext;
        if (req.OwnerWrappedKek is not null) folder.OwnerWrappedKek = req.OwnerWrappedKek;
        if (req.OwnerKemCiphertext is not null) folder.OwnerKemCiphertext = req.OwnerKemCiphertext;
        if (req.MlKemCiphertext is not null) folder.MlKemCiphertext = req.MlKemCiphertext;
        if (req.OwnerMlKemCiphertext is not null) folder.OwnerMlKemCiphertext = req.OwnerMlKemCiphertext;
        if (req.Signature is not null) folder.Signature = req.Signature;

        folder.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            Data = FolderHelper.BuildFolderDto(folder)
        });
    }
}
