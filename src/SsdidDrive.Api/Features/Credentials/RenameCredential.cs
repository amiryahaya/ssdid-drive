using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Credentials;

public static class RenameCredential
{
    private record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, Request request, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var credential = await db.WebAuthnCredentials
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id, ct);

        if (credential is null)
            return AppError.NotFound("Credential not found").ToProblemResult();

        credential.Name = request.Name;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            credential.Id,
            credential.CredentialId,
            credential.Name,
            credential.LastUsedAt,
            credential.CreatedAt
        });
    }
}
