using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Files;

public static class UpdateFile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/files/{fileId:guid}", Handle);

    private record Request(
        string? Status,
        string? BlobHash,
        long? BlobSize,
        int? ChunkCount,
        string? EncryptedMetadata,
        string? Signature);

    private static async Task<IResult> Handle(
        Guid fileId,
        Request request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var fileItem = await db.Files
            .Include(f => f.Folder)
            .FirstOrDefaultAsync(f => f.Id == fileId && f.UploadedById == user.Id, ct);

        if (fileItem is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (request.Status is not null) fileItem.Status = request.Status;
        if (request.BlobHash is not null) fileItem.BlobHash = request.BlobHash;
        if (request.BlobSize is not null) fileItem.BlobSize = request.BlobSize;
        if (request.ChunkCount is not null) fileItem.ChunkCount = request.ChunkCount.Value;
        if (request.EncryptedMetadata is not null) fileItem.EncryptedMetadata = request.EncryptedMetadata;
        if (request.Signature is not null) fileItem.Signature = request.Signature;

        fileItem.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            Data = FileHelper.BuildFileDto(fileItem, fileItem.Folder.TenantId)
        });
    }
}
