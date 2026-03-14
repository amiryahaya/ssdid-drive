using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcCallback
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/callback", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        string provider,
        string? code,
        string? state,
        AppDbContext db,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger,
        OidcTokenValidator validator,
        AuditService auditService,
        InvitationAcceptanceService acceptanceService,
        IConfiguration config,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(code))
            return AppError.BadRequest("Missing authorization code").ToProblemResult();
        if (string.IsNullOrEmpty(state))
            return AppError.BadRequest("Missing state parameter").ToProblemResult();

        var challengeEntry = sessionStore.ConsumeChallenge("oidc", state);
        if (challengeEntry is null)
            return AppError.Unauthorized("Invalid or expired state parameter").ToProblemResult();

        // Parse challenge payload: "codeVerifier|redirect_uri|invitation_token"
        // Backward compatible with old 2-segment format
        var challengePayload = challengeEntry.Challenge;
        var storedProvider = challengeEntry.KeyId;
        var segments = challengePayload.Split('|');
        var codeVerifier = segments[0];
        string? clientRedirectUri = segments.Length > 1 && !string.IsNullOrEmpty(segments[1]) ? segments[1] : null;
        string? invitationToken = segments.Length > 2 && !string.IsNullOrEmpty(segments[2]) ? segments[2] : null;

        if (!string.Equals(storedProvider, provider, StringComparison.OrdinalIgnoreCase))
            return AppError.Unauthorized("State/provider mismatch").ToProblemResult();

        var tokenResult = await exchanger.ExchangeCodeAsync(provider, code, codeVerifier, ct);
        if (!tokenResult.IsSuccess)
            return tokenResult.Error!.ToProblemResult();

        var claims = await validator.ValidateAsync(provider, tokenResult.Value!, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is null)
        {
            // No existing login — check if this is an invitation-based registration
            if (string.IsNullOrEmpty(invitationToken))
                return RedirectWithError(config, "No account linked to this provider. Register first.", clientRedirectUri);

            // Validate invitation
            var invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => (i.Token == invitationToken || i.ShortCode == invitationToken)
                    && i.Status == InvitationStatus.Pending
                    && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

            if (invitation is null)
                return RedirectWithError(config, "Invalid or expired invitation", clientRedirectUri);

            // Email match
            if (!string.IsNullOrEmpty(invitation.Email)
                && !string.Equals(invitation.Email, oidcClaims.Email, StringComparison.OrdinalIgnoreCase))
                return RedirectWithError(config, "Email does not match the invitation", clientRedirectUri);

            // Find or create user
            var existingUser = await db.Users
                .FirstOrDefaultAsync(u => u.Email == oidcClaims.Email, ct);

            User newUser;
            if (existingUser is not null)
            {
                newUser = existingUser;
            }
            else
            {
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

            // Create OIDC login link
            db.Logins.Add(new Login
            {
                AccountId = newUser.Id,
                Provider = providerEnum.Value,
                ProviderSubject = oidcClaims.Subject,
            });

            await db.SaveChangesAsync(ct);

            // Accept invitation via shared service
            var acceptResult = await acceptanceService.AcceptAsync(
                newUser.Id,
                oidcClaims.Email,
                token: invitationToken,
                ct: ct);

            if (!acceptResult.IsSuccess)
                return RedirectWithError(config, acceptResult.Error!.Detail ?? "Failed to accept invitation", clientRedirectUri);

            newUser.LastLoginAt = DateTimeOffset.UtcNow;
            newUser.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);

            var regSessionToken = sessionStore.CreateSession(newUser.Id.ToString());
            if (regSessionToken is null)
                return RedirectWithError(config, "Session limit exceeded", clientRedirectUri);

            await auditService.LogAsync(newUser.Id, "auth.register.oidc", "user", newUser.Id,
                $"Provider: {provider}, via invitation", ct);

            return BuildRedirect(clientRedirectUri, config, regSessionToken, provider,
                mfaRequired: false, totpSetupRequired: false);
        }

        // ── Existing login path (unchanged) ──
        var user = existingLogin.Account;
        if (user.Status == UserStatus.Suspended)
            return RedirectWithError(config, "Account is suspended", clientRedirectUri);

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
                sessionValue = $"mfa:{user.Id}";
                mfaRequired = true;
            }
            else
            {
                sessionValue = user.Id.ToString();
                totpSetupRequired = true;
            }
        }
        else
        {
            sessionValue = user.Id.ToString();
        }

        if (!mfaRequired)
        {
            user.LastLoginAt = DateTimeOffset.UtcNow;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        var sessionToken = sessionStore.CreateSession(sessionValue);
        if (sessionToken is null)
            return RedirectWithError(config, "Session limit exceeded", clientRedirectUri);

        await auditService.LogAsync(user.Id,
            mfaRequired ? "auth.login.oidc.initiated" : "auth.login.oidc",
            "user", user.Id,
            $"Provider: {provider} (server-side)", ct);

        return BuildRedirect(clientRedirectUri, config, sessionToken, provider, mfaRequired, totpSetupRequired);
    }

    private static IResult BuildRedirect(string? clientRedirectUri, IConfiguration config,
        string sessionToken, string provider, bool mfaRequired, bool totpSetupRequired)
    {
        if (clientRedirectUri is not null)
        {
            var separator = clientRedirectUri.Contains('?') ? "&" : "?";
            return Results.Redirect(
                $"{clientRedirectUri}{separator}" +
                $"token={Uri.EscapeDataString(sessionToken)}" +
                $"&provider={Uri.EscapeDataString(provider)}" +
                $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
                $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}");
        }

        var baseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        return Results.Redirect(
            $"{baseUrl}/auth/callback" +
            $"?token={Uri.EscapeDataString(sessionToken)}" +
            $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
            $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}");
    }

    private static IResult RedirectWithError(IConfiguration config, string error, string? clientRedirectUri = null)
    {
        if (clientRedirectUri is not null)
        {
            var separator = clientRedirectUri.Contains('?') ? "&" : "?";
            return Results.Redirect($"{clientRedirectUri}{separator}error={Uri.EscapeDataString(error)}");
        }
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        return Results.Redirect($"{adminBaseUrl}/auth/callback?error={Uri.EscapeDataString(error)}");
    }
}
