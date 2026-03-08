using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class GetPublicKey
{
    // Intentionally not tenant-scoped: cross-tenant key exchange is required
    // for zero-knowledge file sharing between any two users.
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/users/{id:guid}/public-key", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db)
    {
        var user = await db.Users.FindAsync(id);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();
        return Results.Ok(new { user.Id, user.Did, user.PublicKeys });
    }
}
