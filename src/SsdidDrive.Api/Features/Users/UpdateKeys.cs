using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class UpdateKeys
{
    public record Request(
        string? PublicKeys,
        string? EncryptedMasterKey,
        string? EncryptedPrivateKeys,
        string? KeyDerivationSalt);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/me/keys", Handle);

    private const int MaxKeyBlobLength = 65_536; // 64 KB Base64

    private static async Task<IResult> Handle(CurrentUserAccessor accessor, AppDbContext db, Request req)
    {
        var user = await db.Users.FindAsync(accessor.UserId);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        if (req.EncryptedMasterKey is not null && req.EncryptedMasterKey.Length > MaxKeyBlobLength)
            return AppError.BadRequest("EncryptedMasterKey exceeds maximum size").ToProblemResult();
        if (req.EncryptedPrivateKeys is not null && req.EncryptedPrivateKeys.Length > MaxKeyBlobLength)
            return AppError.BadRequest("EncryptedPrivateKeys exceeds maximum size").ToProblemResult();
        if (req.KeyDerivationSalt is not null && req.KeyDerivationSalt.Length > MaxKeyBlobLength)
            return AppError.BadRequest("KeyDerivationSalt exceeds maximum size").ToProblemResult();

        try
        {
            if (req.PublicKeys is not null) user.PublicKeys = req.PublicKeys;
            if (req.EncryptedMasterKey is not null) user.EncryptedMasterKey = Convert.FromBase64String(req.EncryptedMasterKey);
            if (req.EncryptedPrivateKeys is not null) user.EncryptedPrivateKeys = Convert.FromBase64String(req.EncryptedPrivateKeys);
            if (req.KeyDerivationSalt is not null) user.KeyDerivationSalt = Convert.FromBase64String(req.KeyDerivationSalt);
        }
        catch (FormatException)
        {
            return AppError.BadRequest("Invalid Base64 encoding in key data").ToProblemResult();
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Results.Ok(new { user.Id, updated = true });
    }
}
