using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Invitations;

public static class GetInvitationByToken
{
    public static void Map(RouteGroupBuilder group)
    {
        group.MapGet("/token/{token}", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

        // Short code lookup — public but returns only non-PII preview fields
        group.MapGet("/code/{code}", HandleByCode)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");
    }

    private static async Task<IResult> Handle(string token, AppDbContext db, CancellationToken ct)
    {
        // Only accept full token on the public endpoint (not short codes)
        var invitation = await db.Invitations
            .Include(i => i.Tenant)
            .FirstOrDefaultAsync(i =>
                i.Token == token
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found or expired").ToProblemResult();

        return Results.Ok(new
        {
            invitation.Id,
            invitation.TenantId,
            TenantName = invitation.Tenant.Name,
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

    // Short code lookup returns only non-sensitive preview (no email, no user IDs)
    private static async Task<IResult> HandleByCode(string code, AppDbContext db, CancellationToken ct)
    {
        var invitation = await db.Invitations
            .Include(i => i.Tenant)
            .FirstOrDefaultAsync(i =>
                i.ShortCode == code
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found or expired").ToProblemResult();

        return Results.Ok(new
        {
            invitation.Id,
            TenantName = invitation.Tenant.Name,
            Role = invitation.Role.ToString().ToLowerInvariant(),
            invitation.ShortCode,
            invitation.ExpiresAt
        });
    }
}
