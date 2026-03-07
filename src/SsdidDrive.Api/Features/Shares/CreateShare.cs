using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Shares;

public static class CreateShare
{
    public record Request(
        Guid ResourceId,
        string ResourceType,
        Guid SharedWithId,
        string Permission,
        string EncryptedKey,
        string KemAlgorithm,
        DateTimeOffset? ExpiresAt);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (req.ResourceType is not ("file" or "folder"))
            return AppError.BadRequest("Resource type must be 'file' or 'folder'").ToProblemResult();

        if (req.Permission is not ("read" or "write"))
            return AppError.BadRequest("Permission must be 'read' or 'write'").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.EncryptedKey))
            return AppError.BadRequest("Encrypted key is required").ToProblemResult();

        if (req.SharedWithId == user.Id)
            return AppError.BadRequest("Cannot share with yourself").ToProblemResult();

        // Verify the recipient exists
        var recipient = await db.Users.FirstOrDefaultAsync(u => u.Id == req.SharedWithId, ct);
        if (recipient is null)
            return AppError.NotFound("Recipient user not found").ToProblemResult();

        // Verify ownership or admin share access on the resource
        bool isOwner;
        if (req.ResourceType == "folder")
        {
            isOwner = await db.Folders.AnyAsync(f => f.Id == req.ResourceId && f.OwnerId == user.Id, ct);
        }
        else
        {
            isOwner = await db.Files.AnyAsync(f => f.Id == req.ResourceId
                && (f.UploadedById == user.Id || f.Folder.OwnerId == user.Id), ct);
        }

        if (!isOwner)
        {
            // Check if the user has a write share (can re-share)
            var hasWriteShare = await db.Shares.AnyAsync(s =>
                s.ResourceId == req.ResourceId && s.ResourceType == req.ResourceType
                && s.SharedWithId == user.Id && s.Permission == "write"
                && (s.ExpiresAt == null || s.ExpiresAt > DateTimeOffset.UtcNow), ct);

            if (!hasWriteShare)
                return AppError.Forbidden("You do not have permission to share this resource").ToProblemResult();
        }

        // Check for existing share
        var existingShare = await db.Shares.FirstOrDefaultAsync(s =>
            s.ResourceId == req.ResourceId && s.ResourceType == req.ResourceType
            && s.SharedWithId == req.SharedWithId, ct);

        if (existingShare is not null)
            return AppError.Conflict("A share already exists for this resource and user").ToProblemResult();

        var share = new Share
        {
            ResourceId = req.ResourceId,
            ResourceType = req.ResourceType,
            SharedById = user.Id,
            SharedWithId = req.SharedWithId,
            Permission = req.Permission,
            EncryptedKey = Convert.FromBase64String(req.EncryptedKey),
            KemAlgorithm = req.KemAlgorithm,
            ExpiresAt = req.ExpiresAt,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.Shares.Add(share);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/shares/{share.Id}", new
        {
            share.Id,
            share.ResourceId,
            share.ResourceType,
            share.SharedById,
            share.SharedWithId,
            share.Permission,
            EncryptedKey = Convert.ToBase64String(share.EncryptedKey!),
            share.KemAlgorithm,
            share.ExpiresAt,
            share.CreatedAt
        });
    }
}
