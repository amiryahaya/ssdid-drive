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

        // 2. Check expiry first (returns 404 per spec)
        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            if (invitation.Status == InvitationStatus.Pending)
            {
                invitation.Status = InvitationStatus.Expired;
                invitation.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(ct);
            }
            return AppError.NotFound("Invitation has expired").ToProblemResult();
        }

        // 3. Check status (Accepted → 409, others → 404)
        if (invitation.Status == InvitationStatus.Accepted)
            return AppError.Conflict("Invitation has already been accepted").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.NotFound("Invitation not found or is no longer valid").ToProblemResult();

        // 4. Invitation must have an email to verify
        if (string.IsNullOrWhiteSpace(invitation.Email))
            return AppError.BadRequest("Invitation has no email to verify").ToProblemResult();

        // 5. Email match (case-insensitive) — check before credential verification (cheap first)
        if (!string.Equals(req.Email?.Trim(), invitation.Email.Trim(), StringComparison.OrdinalIgnoreCase))
            return AppError.Forbidden("Email verification failed").ToProblemResult();

        // 6. Verify credential
        var verifyResult = auth.VerifyCredential(req.Credential);
        return await verifyResult.Match(
            async did =>
            {
                // 7. Begin transaction for all DB changes
                await using var transaction = await db.Database.BeginTransactionAsync(ct);

                // 8. Find or create user
                var user = await db.Users
                    .FirstOrDefaultAsync(u => u.Did == did, ct);

                var isNewUser = false;
                if (user is null)
                {
                    user = new User
                    {
                        Id = Guid.NewGuid(),
                        Did = did,
                        DisplayName = null,
                        Status = UserStatus.Active,
                        TenantId = invitation.TenantId,
                        CreatedAt = DateTimeOffset.UtcNow,
                        UpdatedAt = DateTimeOffset.UtcNow
                    };
                    isNewUser = true;
                }

                // 9. Check not already a member (direct DB query)
                if (!isNewUser)
                {
                    var existingMembership = await db.UserTenants
                        .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId, ct);
                    if (existingMembership)
                        return AppError.Conflict("User is already a member of this tenant").ToProblemResult();
                }

                // 10. Persist new user (deferred from step 8)
                if (isNewUser)
                {
                    db.Users.Add(user);
                    try
                    {
                        await db.SaveChangesAsync(ct);
                    }
                    catch (Microsoft.EntityFrameworkCore.DbUpdateException)
                    {
                        // Concurrent request created the same DID — re-fetch
                        db.ChangeTracker.Clear();
                        user = await db.Users.FirstAsync(u => u.Did == did, ct);
                    }
                }

                // 11. Accept invitation atomically
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

                // 12. Create UserTenant
                db.UserTenants.Add(new UserTenant
                {
                    UserId = user.Id,
                    TenantId = invitation.TenantId,
                    Role = invitation.Role,
                    CreatedAt = DateTimeOffset.UtcNow
                });

                // 13. Notify inviter
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

                // 14. Create session
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
