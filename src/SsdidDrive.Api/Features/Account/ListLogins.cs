using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Account;

public static class ListLogins
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/logins", Handle);

    private static async Task<IResult> Handle(
        CurrentUserAccessor accessor,
        AppDbContext db,
        CancellationToken ct)
    {
        var logins = await db.Logins
            .AsNoTracking()
            .Where(l => l.AccountId == accessor.UserId)
            .OrderBy(l => l.CreatedAt)
            .Select(l => new
            {
                id = l.Id,
                provider = l.Provider.ToString().ToLowerInvariant(),
                provider_subject = l.ProviderSubject,
                linked_at = l.LinkedAt,
            })
            .ToListAsync(ct);

        return Results.Ok(new { logins });
    }
}
