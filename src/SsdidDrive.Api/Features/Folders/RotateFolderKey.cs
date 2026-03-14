using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class RotateFolderKey
{
    public record MemberKeyEntry(Guid UserId, string EncryptedKey);
    public record Request(string EncryptedFolderKey, string KemAlgorithm, List<MemberKeyEntry>? MemberKeys);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/rotate-key", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (user.TenantId is null)
            return AppError.BadRequest("User does not belong to a tenant").ToProblemResult();

        var folder = await db.Folders
            .FirstOrDefaultAsync(f => f.Id == id && f.TenantId == user.TenantId, ct);

        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != user.Id)
            return AppError.Forbidden("Only the folder owner can rotate the key").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.EncryptedFolderKey))
            return AppError.BadRequest("Encrypted folder key is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.KemAlgorithm))
            return AppError.BadRequest("KEM algorithm is required").ToProblemResult();

        // Update folder key
        folder.EncryptedFolderKey = Convert.FromBase64String(req.EncryptedFolderKey);
        folder.KemAlgorithm = req.KemAlgorithm;
        folder.FolderKeyVersion++;
        folder.UpdatedAt = DateTimeOffset.UtcNow;

        // Update member share keys
        if (req.MemberKeys is { Count: > 0 })
        {
            var memberUserIds = req.MemberKeys.Select(m => m.UserId).ToList();
            var existingShares = await db.Shares
                .Where(s =>
                    s.ResourceId == id &&
                    s.ResourceType == "folder" &&
                    s.RevokedAt == null &&
                    memberUserIds.Contains(s.SharedWithId))
                .ToListAsync(ct);

            foreach (var memberKey in req.MemberKeys)
            {
                var share = existingShares.FirstOrDefault(s => s.SharedWithId == memberKey.UserId);
                if (share is not null)
                {
                    share.EncryptedKey = Convert.FromBase64String(memberKey.EncryptedKey);
                    share.KemAlgorithm = req.KemAlgorithm;
                }
                // Skip if no existing share for this user
            }
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(new { folder.FolderKeyVersion });
    }
}
