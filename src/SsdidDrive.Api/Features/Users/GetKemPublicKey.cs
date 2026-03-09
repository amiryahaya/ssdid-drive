using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class GetKemPublicKey
{
    // Cross-tenant: any authenticated user can fetch another user's KEM public key
    // for zero-knowledge file encryption key exchange.
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/users/{id:guid}/kem-public-key", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db)
    {
        var user = await db.Users.FindAsync(id);
        if (user is null || user.KemPublicKey is null)
            return AppError.NotFound("User not found or no KEM key set").ToProblemResult();

        return Results.Ok(new
        {
            user.Id,
            KemPublicKey = Convert.ToBase64String(user.KemPublicKey),
            user.KemAlgorithm
        });
    }
}
