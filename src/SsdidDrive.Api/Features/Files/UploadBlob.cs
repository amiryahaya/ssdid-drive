using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Files;

public static class UploadBlob
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/files/{fileId:guid}/blob", Handle);

    private static async Task<IResult> Handle(
        Guid fileId,
        HttpRequest request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        IStorageService storage,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var fileItem = await db.Files
            .FirstOrDefaultAsync(f => f.Id == fileId && f.UploadedById == user.Id, ct);

        if (fileItem is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (fileItem.Status != "pending")
            return AppError.BadRequest("File is not in pending status").ToProblemResult();

        // Store the blob content
        await storage.StoreAsync(
            user.TenantId!.Value,
            fileItem.FolderId,
            fileItem.Id,
            request.Body,
            ct);

        fileItem.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new { Status = "uploaded" });
    }
}
