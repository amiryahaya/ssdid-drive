using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Files;

public static class RenameFile
{
    public record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/files/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length > 512)
            return AppError.BadRequest("File name is required (max 512 chars)").ToProblemResult();

        var user = accessor.User!;

        var file = await db.Files
            .Include(f => f.Folder)
            .FirstOrDefaultAsync(f => f.Id == id && f.Folder.TenantId == user.TenantId, ct);

        if (file is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (file.UploadedById != user.Id)
            return AppError.Forbidden("Only the file uploader can rename it").ToProblemResult();

        file.Name = req.Name.Trim();
        file.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            file.Id,
            file.Name,
            file.ContentType,
            file.Size,
            file.FolderId,
            file.UploadedById,
            EncryptedFileKey = file.EncryptedFileKey is not null
                ? Convert.ToBase64String(file.EncryptedFileKey)
                : null,
            Nonce = file.Nonce is not null
                ? Convert.ToBase64String(file.Nonce)
                : null,
            file.EncryptionAlgorithm,
            file.CreatedAt,
            file.UpdatedAt
        });
    }
}
