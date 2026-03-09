using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Credentials;

public static class DeleteCredential
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var credential = await db.WebAuthnCredentials
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id, ct);

        if (credential is null)
            return AppError.NotFound("Credential not found").ToProblemResult();

        var count = await db.WebAuthnCredentials.CountAsync(c => c.UserId == user.Id, ct);
        if (count <= 1)
            return AppError.BadRequest("Cannot delete the last credential").ToProblemResult();

        db.WebAuthnCredentials.Remove(credential);
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
