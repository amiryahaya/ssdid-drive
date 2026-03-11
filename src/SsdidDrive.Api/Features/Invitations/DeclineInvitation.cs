using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class DeclineInvitation
{
    public record Request(string? Token = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/decline", Handle);

    private static async Task<IResult> Handle(Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id && i.Status == InvitationStatus.Pending, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        // Authorization: if InvitedUserId is set, only that user can decline.
        if (invitation.InvitedUserId is not null && invitation.InvitedUserId != user.Id)
            return AppError.Forbidden("You are not the invited user").ToProblemResult();

        // For open invitations, require token proof
        if (invitation.InvitedUserId is null)
        {
            if (string.IsNullOrWhiteSpace(req.Token) || req.Token != invitation.Token)
                return AppError.Forbidden("Invalid or missing invitation token").ToProblemResult();
        }

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
