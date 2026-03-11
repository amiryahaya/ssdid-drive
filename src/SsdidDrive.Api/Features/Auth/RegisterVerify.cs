using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class RegisterVerify
{
    public record Request(
        string Did,
        string KeyId,
        string SignedChallenge,
        string? InviteToken = null,
        Dictionary<string, string>? SharedClaims = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/register/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth, AppDbContext db, IConfiguration config)
    {
        if (string.IsNullOrWhiteSpace(req.Did) || !req.Did.StartsWith("did:ssdid:") || req.Did.Length > 256)
            return AppError.BadRequest("Invalid DID format").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyId) || req.KeyId.Length > 512)
            return AppError.BadRequest("Invalid KeyId").ToProblemResult();
        // PQC signatures are large: ML-DSA-44 ~3.2K, SLH-DSA-SHA2-256f ~66K base64 chars
        if (string.IsNullOrWhiteSpace(req.SignedChallenge) || req.SignedChallenge.Length > 100_000)
            return AppError.BadRequest("Invalid SignedChallenge").ToProblemResult();

        var result = await auth.HandleVerifyResponse(req.Did, req.KeyId, req.SignedChallenge);
        return await result.Match(
            async ok =>
            {
                var adminDid = config["Ssdid:AdminDid"];
                var user = await ProvisionUser(db, req.Did, req.InviteToken, req.SharedClaims, adminDid);
                if (user is null)
                    return AppError.Forbidden("Registration requires a valid invite code").ToProblemResult();
                return Results.Created($"/api/users/{user.Id}", ok);
            },
            err => Task.FromResult(err.ToProblemResult()));
    }

    private static async Task<User?> ProvisionUser(
        AppDbContext db, string did, string? inviteToken,
        Dictionary<string, string>? claims, string? adminDid)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Did == did);
        if (user is not null)
        {
            // Existing user — update claims on re-registration (wallet may have updated profile)
            ApplyClaims(user, claims);

            // If invite token provided, accept it for the existing user
            if (!string.IsNullOrWhiteSpace(inviteToken))
            {
                await using var tx = await db.Database.BeginTransactionAsync();
                try
                {
                    await AcceptInviteForUser(db, user, inviteToken);
                    await db.SaveChangesAsync();
                    await tx.CommitAsync();
                }
                catch
                {
                    await tx.RollbackAsync();
                    db.ChangeTracker.Clear();
                    // Re-fetch user after rollback
                    user = await db.Users.FirstOrDefaultAsync(u => u.Did == did);
                }
            }
            else
            {
                await db.SaveChangesAsync();
            }

            return user;
        }

        // New user — require invite token (except for AdminDid bootstrap)
        var isAdmin = !string.IsNullOrEmpty(adminDid) && did == adminDid;

        Invitation? invitation = null;
        if (!string.IsNullOrWhiteSpace(inviteToken))
        {
            // Only accept full token — short codes have insufficient entropy for registration
            invitation = await db.Invitations
                .FirstOrDefaultAsync(i =>
                    i.Token == inviteToken
                    && i.Status == InvitationStatus.Pending
                    && i.ExpiresAt > DateTimeOffset.UtcNow);
        }

        // Reject registration without invite (unless admin bootstrap)
        if (invitation is null && !isAdmin)
            return null;

        await using var newUserTx = await db.Database.BeginTransactionAsync();
        try
        {
            user = new User
            {
                Id = Guid.NewGuid(),
                Did = did,
                TenantId = invitation?.TenantId,
                SystemRole = isAdmin ? SystemRole.SuperAdmin : null
            };
            ApplyClaims(user, claims);
            db.Users.Add(user);

            if (invitation is not null)
            {
                // Join the invite's tenant with the assigned role
                db.UserTenants.Add(new UserTenant
                {
                    UserId = user.Id,
                    TenantId = invitation.TenantId,
                    Role = invitation.Role,
                    CreatedAt = DateTimeOffset.UtcNow
                });

                // Mark invitation as accepted
                invitation.Status = InvitationStatus.Accepted;
                invitation.InvitedUserId = user.Id;
                invitation.UpdatedAt = DateTimeOffset.UtcNow;
            }
            else if (isAdmin)
            {
                // Admin bootstrap: create a personal tenant
                var tenant = new Tenant
                {
                    Id = Guid.NewGuid(),
                    Name = "Personal",
                    Slug = $"personal-{Guid.NewGuid():N}"
                };
                db.Tenants.Add(tenant);

                user.TenantId = tenant.Id;

                db.UserTenants.Add(new UserTenant
                {
                    UserId = user.Id,
                    TenantId = tenant.Id,
                    Role = TenantRole.Owner,
                    CreatedAt = DateTimeOffset.UtcNow
                });
            }

            await db.SaveChangesAsync();
            await newUserTx.CommitAsync();
            return user;
        }
        catch (DbUpdateException)
        {
            await newUserTx.RollbackAsync();
            db.ChangeTracker.Clear();
            var existing = await db.Users.FirstOrDefaultAsync(u => u.Did == did);
            return existing ?? throw new InvalidOperationException(
                $"User provisioning failed for DID {did}: concurrent insert expected but user not found");
        }
    }

    private static async Task AcceptInviteForUser(AppDbContext db, User user, string inviteToken)
    {
        // Only accept full token — short codes have insufficient entropy
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i =>
                i.Token == inviteToken
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow);

        if (invitation is null) return;

        // Check not already a member
        var alreadyMember = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId);
        if (alreadyMember) return;

        db.UserTenants.Add(new UserTenant
        {
            UserId = user.Id,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
            CreatedAt = DateTimeOffset.UtcNow
        });

        invitation.Status = InvitationStatus.Accepted;
        invitation.InvitedUserId = user.Id;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;

        // Set as active tenant if user doesn't have one
        if (user.TenantId is null)
            user.TenantId = invitation.TenantId;
    }

    private static void ApplyClaims(User user, Dictionary<string, string>? claims)
    {
        if (claims is null || claims.Count == 0) return;

        if (claims.TryGetValue("name", out var name) && !string.IsNullOrWhiteSpace(name))
            user.DisplayName = name.Trim()[..Math.Min(name.Trim().Length, 200)];

        if (claims.TryGetValue("email", out var email) && !string.IsNullOrWhiteSpace(email))
            user.Email = email.Trim()[..Math.Min(email.Trim().Length, 320)];
    }
}
