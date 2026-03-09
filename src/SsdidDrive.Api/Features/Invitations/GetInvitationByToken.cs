using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Invitations;

public static class GetInvitationByToken
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/token/{token}", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(string token, AppDbContext db, CancellationToken ct)
    {
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Token == token
                && i.Status == InvitationStatus.Pending, ct);

        // Check expiry client-side for SQLite compatibility
        if (invitation is null || invitation.ExpiresAt <= DateTimeOffset.UtcNow)
            return AppError.NotFound("Invitation not found or expired").ToProblemResult();

        return Results.Ok(new
        {
            invitation.Id,
            invitation.TenantId,
            invitation.InvitedById,
            invitation.Email,
            invitation.InvitedUserId,
            Role = invitation.Role.ToString().ToLowerInvariant(),
            Status = invitation.Status.ToString().ToLowerInvariant(),
            invitation.Message,
            invitation.ExpiresAt,
            invitation.CreatedAt
        });
    }
}
