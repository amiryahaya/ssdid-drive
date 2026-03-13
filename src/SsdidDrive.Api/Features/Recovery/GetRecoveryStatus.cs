using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryStatus
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/status", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var setup = await db.RecoverySetups
            .Where(rs => rs.UserId == user.Id && rs.IsActive)
            .Select(rs => new { rs.ShareCreatedAt })
            .FirstOrDefaultAsync(ct);

        return Results.Ok(new
        {
            is_active = setup is not null,
            created_at = setup?.ShareCreatedAt
        });
    }
}
