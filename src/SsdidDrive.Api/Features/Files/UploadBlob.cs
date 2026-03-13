using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class UploadBlob
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/files/{fileId:guid}/blob", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Guid fileId,
        HttpRequest request,
        AppDbContext db,
        IStorageService storage,
        CancellationToken ct)
    {
        // No auth required — the file ID (random UUID) acts as the upload token.
        // Only files in "pending" status accept blob uploads, and only the creator
        // received the upload URL.
        var fileItem = await db.Files
            .FirstOrDefaultAsync(f => f.Id == fileId && f.Status == "pending", ct);

        if (fileItem is null)
            return AppError.NotFound("File not found or upload already completed").ToProblemResult();

        // Resolve tenant ID from the folder
        var folder = await db.Folders.FindAsync([fileItem.FolderId], ct);
        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        // Store the blob content
        await storage.StoreAsync(
            folder.TenantId,
            fileItem.FolderId,
            fileItem.Id,
            request.Body,
            ct);

        fileItem.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new { Status = "uploaded" });
    }
}
