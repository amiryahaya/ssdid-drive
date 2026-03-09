using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class ListInvitations
{
    public static void Map(RouteGroupBuilder group)
    {
        group.MapGet("/", HandleReceived);
        group.MapGet("/sent", HandleSent);
    }

    private static async Task<IResult> HandleReceived(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitations = (await db.Invitations
            .Where(i => i.Status == InvitationStatus.Pending
                && (i.InvitedUserId == user.Id
                    || (user.Email != null && i.Email == user.Email)))
            .ToListAsync(ct))
            .OrderByDescending(i => i.CreatedAt)
            .Select(ToDto)
            .ToList();

        return Results.Ok(invitations);
    }

    private static async Task<IResult> HandleSent(AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitations = (await db.Invitations
            .Where(i => i.InvitedById == user.Id)
            .ToListAsync(ct))
            .OrderByDescending(i => i.CreatedAt)
            .Select(ToDto)
            .ToList();

        return Results.Ok(invitations);
    }

    private static object ToDto(Invitation i) => new
    {
        i.Id,
        i.TenantId,
        i.InvitedById,
        i.Email,
        i.InvitedUserId,
        Role = i.Role.ToString().ToLowerInvariant(),
        Status = i.Status.ToString().ToLowerInvariant(),
        i.Token,
        i.Message,
        i.ExpiresAt,
        i.CreatedAt
    };
}
