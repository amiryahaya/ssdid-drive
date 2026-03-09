using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class PublishKemKey
{
    public record Request(string? KemPublicKey, string? KemAlgorithm);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/me/keys/kem", Handle);

    private static async Task<IResult> Handle(CurrentUserAccessor accessor, AppDbContext db, Request req)
    {
        if (string.IsNullOrWhiteSpace(req.KemPublicKey))
            return AppError.BadRequest("kem_public_key is required").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KemAlgorithm))
            return AppError.BadRequest("kem_algorithm is required").ToProblemResult();

        var user = await db.Users.FindAsync(accessor.UserId);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        try
        {
            user.KemPublicKey = Convert.FromBase64String(req.KemPublicKey);
        }
        catch (FormatException)
        {
            return AppError.BadRequest("kem_public_key must be valid Base64").ToProblemResult();
        }

        user.KemAlgorithm = req.KemAlgorithm;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Results.Ok(new { user.Id, updated = true });
    }
}
