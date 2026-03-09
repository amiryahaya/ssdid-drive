using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class RevokeInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(Guid id, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        if (invitation.InvitedById != user.Id)
            return AppError.Forbidden("Only the invitation creator can revoke it").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.BadRequest("Only pending invitations can be revoked").ToProblemResult();

        invitation.Status = InvitationStatus.Revoked;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
