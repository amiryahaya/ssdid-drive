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
        IConfiguration config,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(code))
            return AppError.BadRequest("Missing authorization code").ToProblemResult();
        if (string.IsNullOrEmpty(state))
            return AppError.BadRequest("Missing state parameter").ToProblemResult();

        // Validate and consume state
        var challengeEntry = sessionStore.ConsumeChallenge("oidc", state);
        if (challengeEntry is null)
            return AppError.Unauthorized("Invalid or expired state parameter").ToProblemResult();

        // Challenge payload may contain redirect_uri: "codeVerifier|redirect_uri"
        var challengePayload = challengeEntry.Challenge;
        var storedProvider = challengeEntry.KeyId;
        string codeVerifier;
        string? clientRedirectUri = null;

        var pipeIndex = challengePayload.IndexOf('|');
        if (pipeIndex >= 0)
        {
            codeVerifier = challengePayload[..pipeIndex];
            clientRedirectUri = challengePayload[(pipeIndex + 1)..];
        }
        else
        {
            codeVerifier = challengePayload;
        }

        if (!string.Equals(storedProvider, provider, StringComparison.OrdinalIgnoreCase))
            return AppError.Unauthorized("State/provider mismatch").ToProblemResult();

        // Exchange code for ID token
        var tokenResult = await exchanger.ExchangeCodeAsync(provider, code, codeVerifier, ct);
        if (!tokenResult.IsSuccess)
            return tokenResult.Error!.ToProblemResult();

        // Validate ID token
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

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is null)
            return RedirectWithError(config, "No account linked to this provider. Register first.", clientRedirectUri);

        var user = existingLogin.Account;
        if (user.Status == UserStatus.Suspended)
            return RedirectWithError(config, "Account is suspended", clientRedirectUri);

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
                // Admin without TOTP — full session so they can call /totp/setup
                sessionValue = user.Id.ToString();
                totpSetupRequired = true;
            }
        }
        else
        {
            sessionValue = user.Id.ToString();
        }

        // Only stamp LastLoginAt for completed logins (not MFA-pending)
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

        // Redirect to the originating client
        var baseUrl = clientRedirectUri ?? config["AdminPortal:BaseUrl"] ?? "/admin";
        string redirectUrl;

        if (clientRedirectUri is not null)
        {
            // Desktop deep link: append token as query param
            var separator = clientRedirectUri.Contains('?') ? "&" : "?";
            redirectUrl = $"{clientRedirectUri}{separator}" +
                $"token={Uri.EscapeDataString(sessionToken)}" +
                $"&provider={Uri.EscapeDataString(provider)}" +
                $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
                $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}";
        }
        else
        {
            // Admin portal
            redirectUrl = $"{baseUrl}/auth/callback" +
                $"?token={Uri.EscapeDataString(sessionToken)}" +
                $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
                $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}";
        }

        return Results.Redirect(redirectUrl);
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
