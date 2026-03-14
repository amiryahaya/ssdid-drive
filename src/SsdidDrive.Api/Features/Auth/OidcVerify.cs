using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcVerify
{
    public record Request(string Provider, string IdToken, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/oidc/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OidcTokenValidator validator,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Provider) || string.IsNullOrWhiteSpace(req.IdToken))
            return AppError.BadRequest("Provider and id_token are required").ToProblemResult();

        var claims = await validator.ValidateAsync(req.Provider, req.IdToken, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = req.Provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null,
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is not null)
        {
            var user = existingLogin.Account;
            if (user.Status == UserStatus.Suspended)
                return AppError.Forbidden("Account is suspended").ToProblemResult();

            user.LastLoginAt = DateTimeOffset.UtcNow;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);

            // Check if user is admin/owner in any tenant
            var isAdmin = await db.UserTenants
                .AnyAsync(ut => ut.UserId == user.Id
                    && (ut.Role == TenantRole.Owner || ut.Role == TenantRole.Admin), ct);

            string sessionValue;
            bool mfaRequired = false;
            bool totpSetupRequired = false;

            if (isAdmin)
            {
                if (user.TotpEnabled)
                {
                    // Admin with TOTP — require MFA verification
                    sessionValue = $"mfa:{user.Id}";
                    mfaRequired = true;
                }
                else
                {
                    // Admin without TOTP — require TOTP setup
                    sessionValue = user.Id.ToString(); // Full session so they can call /totp/setup
                    totpSetupRequired = true;
                }
            }
            else
            {
                sessionValue = user.Id.ToString();
            }

            var token = sessionStore.CreateSession(sessionValue);
            if (token is null)
                return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

            await auditService.LogAsync(user.Id, "auth.login.oidc", "user", user.Id,
                $"Provider: {req.Provider}", ct);

            return Results.Ok(new
            {
                token,
                account_id = user.Id,
                email = user.Email,
                display_name = user.DisplayName,
                mfa_required = mfaRequired,
                totp_setup_required = totpSetupRequired,
            });
        }

        // No existing login -- need invitation for registration
        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.NotFound("No account linked to this provider. Register first or link in Settings.").ToProblemResult();

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Token == req.InvitationToken
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        var newUser = new User
        {
            Email = oidcClaims.Email,
            DisplayName = oidcClaims.Name,
            EmailVerified = true,
            Status = UserStatus.Active,
            TenantId = invitation.TenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        db.Users.Add(newUser);

        db.Logins.Add(new Login
        {
            AccountId = newUser.Id,
            Provider = providerEnum.Value,
            ProviderSubject = oidcClaims.Subject,
        });

        invitation.Status = InvitationStatus.Accepted;
        invitation.InvitedUserId = newUser.Id;
        invitation.AcceptedAt = DateTimeOffset.UtcNow;

        db.UserTenants.Add(new UserTenant
        {
            UserId = newUser.Id,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
        });

        await db.SaveChangesAsync(ct);

        var newToken = sessionStore.CreateSession(newUser.Id.ToString());
        if (newToken is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(newUser.Id, "auth.register.oidc", "user", newUser.Id,
            $"Provider: {req.Provider}", ct);

        return Results.Ok(new
        {
            token = newToken,
            account_id = newUser.Id,
            email = newUser.Email,
            display_name = newUser.DisplayName,
            is_new_account = true,
        });
    }
}
