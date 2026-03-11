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
        // Support both full token and short code lookup
        var invitation = await db.Invitations
            .Include(i => i.Tenant)
            .FirstOrDefaultAsync(i =>
                (i.Token == token || i.ShortCode == token)
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found or expired").ToProblemResult();

        return Results.Ok(new
        {
            invitation.Id,
            invitation.TenantId,
            tenant_name = invitation.Tenant.Name,
            invitation.InvitedById,
            invitation.Email,
            invitation.InvitedUserId,
            Role = invitation.Role.ToString().ToLowerInvariant(),
            Status = invitation.Status.ToString().ToLowerInvariant(),
            invitation.ShortCode,
            invitation.Message,
            invitation.ExpiresAt,
            invitation.CreatedAt
        });
    }
}
