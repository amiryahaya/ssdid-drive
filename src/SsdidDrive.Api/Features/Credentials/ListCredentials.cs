using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Credentials;

public static class ListCredentials
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var credentials = (await db.WebAuthnCredentials
            .Where(c => c.UserId == user.Id)
            .ToListAsync(ct))
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new
            {
                c.Id,
                c.CredentialId,
                c.Name,
                c.LastUsedAt,
                c.CreatedAt
            })
            .ToList();

        return Results.Ok(credentials);
    }
}
