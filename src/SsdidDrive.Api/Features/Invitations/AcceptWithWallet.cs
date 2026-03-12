using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptWithWallet
{
    public record Request(JsonElement Credential, string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/token/{token}/accept-with-wallet", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        string token,
        Request req,
        AppDbContext db,
        SsdidAuthService auth,
        NotificationService notifications,
        CancellationToken ct)
    {
        // 1. Look up invitation by token (without status filter to distinguish 404 vs 409)
        var invitation = await db.Invitations
            .Include(i => i.Tenant)
            .Include(i => i.InvitedBy)
            .FirstOrDefaultAsync(i => i.Token == token, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.Conflict("Invitation has already been " + invitation.Status.ToString().ToLowerInvariant()).ToProblemResult();

        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            invitation.Status = InvitationStatus.Expired;
            invitation.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return AppError.NotFound("Invitation has expired").ToProblemResult();
        }

        // 2. Verify credential
        var verifyResult = auth.VerifyCredential(req.Credential);
        return await verifyResult.Match(
            async did =>
            {
                // 3. Email match (case-insensitive)
                if (!string.Equals(req.Email?.Trim(), invitation.Email?.Trim(), StringComparison.OrdinalIgnoreCase))
                    return AppError.Forbidden("Email verification failed").ToProblemResult();

                // 4. Begin transaction for all DB changes
                await using var transaction = await db.Database.BeginTransactionAsync(ct);

                // 5. Find or create user
                var user = await db.Users
                    .FirstOrDefaultAsync(u => u.Did == did, ct);

                if (user is null)
                {
                    user = new User
                    {
                        Id = Guid.NewGuid(),
                        Did = did,
                        DisplayName = req.Email,
                        Status = UserStatus.Active,
                        TenantId = invitation.TenantId,
                        CreatedAt = DateTimeOffset.UtcNow,
                        UpdatedAt = DateTimeOffset.UtcNow
                    };
                    db.Users.Add(user);
                    await db.SaveChangesAsync(ct);
                }

                // 6. Check not already a member (direct DB query)
                var existingMembership = await db.UserTenants
                    .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId, ct);
                if (existingMembership)
                    return AppError.Conflict("User is already a member of this tenant").ToProblemResult();

                // 7. Accept invitation atomically
                var updated = await db.Invitations
                    .Where(i => i.Id == invitation.Id && i.Status == InvitationStatus.Pending)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(i => i.Status, InvitationStatus.Accepted)
                        .SetProperty(i => i.InvitedUserId, user.Id)
                        .SetProperty(i => i.AcceptedByDid, did)
                        .SetProperty(i => i.AcceptedAt, DateTimeOffset.UtcNow)
                        .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

                if (updated == 0)
                    return AppError.Conflict("Invitation has already been processed").ToProblemResult();

                // 8. Create UserTenant
                db.UserTenants.Add(new UserTenant
                {
                    UserId = user.Id,
                    TenantId = invitation.TenantId,
                    Role = invitation.Role,
                    CreatedAt = DateTimeOffset.UtcNow
                });

                // 9. Notify inviter
                await notifications.CreateAsync(
                    invitation.InvitedById,
                    "invitation_accepted",
                    "Invitation Accepted",
                    $"{user.DisplayName ?? user.Did} accepted your invitation",
                    actionType: "invitation",
                    actionResourceId: invitation.Id.ToString(),
                    ct: ct);

                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);

                // 10. Create session
                var sessionResult = auth.CreateAuthenticatedSession(did);
                return sessionResult.Match(
                    ok => Results.Ok(new
                    {
                        session_token = ok.SessionToken,
                        did = ok.Did,
                        server_did = ok.ServerDid,
                        server_key_id = ok.ServerKeyId,
                        server_signature = ok.ServerSignature,
                        user = new
                        {
                            user.Id,
                            user.Did,
                            display_name = user.DisplayName,
                            status = user.Status.ToString().ToLowerInvariant()
                        },
                        tenant = new
                        {
                            id = invitation.TenantId,
                            name = invitation.Tenant.Name,
                            slug = invitation.Tenant.Slug,
                            role = invitation.Role.ToString().ToLowerInvariant()
                        }
                    }),
                    err => err.ToProblemResult());
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
