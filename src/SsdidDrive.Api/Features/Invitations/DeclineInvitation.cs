using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class DeclineInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/decline", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id && i.Status == InvitationStatus.Pending, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        // Only the invited user can decline
        var isInvitedUser = invitation.InvitedUserId == user.Id
            || (user.Email != null && invitation.Email == user.Email);

        if (!isInvitedUser)
            return AppError.Forbidden("You are not the invited user").ToProblemResult();

        invitation.Status = InvitationStatus.Declined;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            invitation.Id,
            Status = invitation.Status.ToString().ToLowerInvariant()
        });
    }
}
