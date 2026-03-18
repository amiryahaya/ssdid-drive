using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

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
                session_token = token,
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

        var invToken = req.InvitationToken!.Trim();
        // Materialize first, filter client-side (SQLite compat: DateTimeOffset/enum in WHERE)
        var verifyNow = DateTimeOffset.UtcNow;
        var invCandidates = await db.Invitations
            .Where(i => i.Token == invToken || i.ShortCode == invToken)
            .ToListAsync(ct);
        var invitation = invCandidates
            .FirstOrDefault(i => i.Status == InvitationStatus.Pending && i.ExpiresAt > verifyNow);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // If invitation specifies an email, the OIDC email must match
        if (!string.IsNullOrEmpty(invitation.Email)
            && !string.Equals(invitation.Email, oidcClaims.Email, StringComparison.OrdinalIgnoreCase))
            return AppError.Forbidden($"This invitation is for {invitation.Email}").ToProblemResult();

        // Auto-link: check if a user with this email already exists
        var newUser = await db.Users.FirstOrDefaultAsync(
            u => u.Email == oidcClaims.Email, ct);

        if (newUser is not null)
        {
            // Link OIDC login to existing account
            newUser.DisplayName ??= oidcClaims.Name;
            newUser.EmailVerified = true;
            newUser.UpdatedAt = DateTimeOffset.UtcNow;
        }
        else
        {
            // Create new user
            newUser = new User
            {
                Id = Guid.NewGuid(),
                Email = oidcClaims.Email,
                DisplayName = oidcClaims.Name,
                EmailVerified = true,
                Status = UserStatus.Active,
                TenantId = invitation.TenantId,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow,
            };
            db.Users.Add(newUser);
        }

        // Add OIDC login link if not already linked
        var hasOidcLogin = await db.Logins.AnyAsync(
            l => l.AccountId == newUser.Id
                && l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);
        if (!hasOidcLogin)
        {
            db.Logins.Add(new Login
            {
                AccountId = newUser.Id,
                Provider = providerEnum.Value,
                ProviderSubject = oidcClaims.Subject,
            });
        }

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
            session_token = newToken,
            account_id = newUser.Id,
            email = newUser.Email,
            display_name = newUser.DisplayName,
            is_new_account = true,
        });
    }
}
