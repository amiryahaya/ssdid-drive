using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class ListTrustees
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/trustees", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var setup = await db.RecoverySetups
            .Where(rs => rs.UserId == user.Id && rs.IsActive)
            .Select(rs => new { rs.Id, rs.Threshold })
            .FirstOrDefaultAsync(ct);

        if (setup is null)
            return Results.Ok(new { trustees = Array.Empty<object>(), threshold = 0 });

        var trustees = await db.RecoveryTrustees
            .Where(rt => rt.RecoverySetupId == setup.Id)
            .Select(rt => new
            {
                id = rt.Id,
                trustee_user_id = rt.TrusteeUserId,
                display_name = rt.TrusteeUser.DisplayName,
                email = rt.TrusteeUser.Email,
                share_index = rt.ShareIndex,
                created_at = rt.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            trustees,
            threshold = setup.Threshold
        });
    }
}
