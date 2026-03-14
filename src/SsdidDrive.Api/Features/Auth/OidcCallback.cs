using System.Security.Cryptography;
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
    public static void Map(RouteGroupBuilder group)
    {
        group.MapGet("/oidc/{provider}/callback", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

        group.MapPost("/oidc/exchange", HandleExchange)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");
    }

    /// <summary>
    /// Error codes used in the redirect URL — the frontend maps these to user-friendly messages.
    /// Never reflect raw error text from query params.
    /// </summary>
    private static class ErrorCodes
    {
        public const string NoAccount = "no_account";
        public const string Suspended = "suspended";
        public const string SessionLimit = "session_limit";
        public const string InvalidCode = "invalid_code";
        public const string InvalidState = "invalid_state";
        public const string ProviderError = "provider_error";
    }

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
            return RedirectWithError(config, ErrorCodes.InvalidCode);
        if (string.IsNullOrEmpty(state))
            return RedirectWithError(config, ErrorCodes.InvalidState);

        // Validate and consume state
        var challengeEntry = sessionStore.ConsumeChallenge("oidc", state);
        if (challengeEntry is null)
            return RedirectWithError(config, ErrorCodes.InvalidState);

        var codeVerifier = challengeEntry.Challenge;
        var storedProvider = challengeEntry.KeyId;

        if (!string.Equals(storedProvider, provider, StringComparison.OrdinalIgnoreCase))
            return RedirectWithError(config, ErrorCodes.InvalidState);

        // Exchange code for ID token
        var tokenResult = await exchanger.ExchangeCodeAsync(provider, code, codeVerifier, ct);
        if (!tokenResult.IsSuccess)
            return RedirectWithError(config, ErrorCodes.ProviderError);

        // Validate ID token
        var claims = await validator.ValidateAsync(provider, tokenResult.Value!, ct);
        if (!claims.IsSuccess)
            return RedirectWithError(config, ErrorCodes.ProviderError);

        var oidcClaims = claims.Value!;
        var providerEnum = provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null
        };

        if (providerEnum is null)
            return RedirectWithError(config, ErrorCodes.ProviderError);

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is null)
            return RedirectWithError(config, ErrorCodes.NoAccount);

        var user = existingLogin.Account;
        if (user.Status == UserStatus.Suspended)
            return RedirectWithError(config, ErrorCodes.Suspended);

        // Check if user is admin/owner in any tenant
        var isAdmin = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id
                && (ut.Role == TenantRole.Owner || ut.Role == TenantRole.Admin), ct);

        string sessionValue;
        string mfaState = "none"; // none | mfa_required | totp_setup_required

        if (isAdmin)
        {
            if (user.TotpEnabled)
            {
                // Admin with TOTP — require MFA verification (restricted session)
                sessionValue = $"mfa:{user.Id}";
                mfaState = "mfa_required";
            }
            else
            {
                // Admin without TOTP — restricted session for setup only
                sessionValue = $"setup:{user.Id}";
                mfaState = "totp_setup_required";
            }
        }
        else
        {
            sessionValue = user.Id.ToString();
        }

        // Only stamp LastLoginAt for completed logins (not MFA-pending)
        if (mfaState == "none")
        {
            user.LastLoginAt = DateTimeOffset.UtcNow;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        var sessionToken = sessionStore.CreateSession(sessionValue);
        if (sessionToken is null)
            return RedirectWithError(config, ErrorCodes.SessionLimit);

        await auditService.LogAsync(user.Id,
            mfaState != "none" ? "auth.login.oidc.initiated" : "auth.login.oidc",
            "user", user.Id,
            $"Provider: {provider} (server-side)", ct);

        // Store session token as a one-time exchange code (never expose token in URL)
        var exchangeCode = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        sessionStore.CreateChallenge(exchangeCode, "oidc_exchange", sessionToken, mfaState);

        // Redirect with only the opaque exchange code
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        var redirectUrl = $"{adminBaseUrl}/auth/callback?code={Uri.EscapeDataString(exchangeCode)}";

        return Results.Redirect(redirectUrl);
    }

    /// <summary>
    /// Exchange a one-time code for the session token. Called by the admin portal frontend.
    /// </summary>
    public record ExchangeRequest(string Code);

    private static Task<IResult> HandleExchange(
        ExchangeRequest req,
        ISessionStore sessionStore)
    {
        if (string.IsNullOrWhiteSpace(req.Code))
            return Task.FromResult(AppError.BadRequest("Missing exchange code").ToProblemResult());

        var entry = sessionStore.ConsumeChallenge(req.Code, "oidc_exchange");
        if (entry is null)
            return Task.FromResult(AppError.Unauthorized("Invalid or expired code").ToProblemResult());

        var sessionToken = entry.Challenge;
        var mfaState = entry.KeyId; // "none" | "mfa_required" | "totp_setup_required"

        return Task.FromResult(Results.Ok(new
        {
            token = sessionToken,
            mfa_required = mfaState == "mfa_required",
            totp_setup_required = mfaState == "totp_setup_required"
        }));
    }

    private static IResult RedirectWithError(IConfiguration config, string errorCode)
    {
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        return Results.Redirect($"{adminBaseUrl}/auth/callback?error={Uri.EscapeDataString(errorCode)}");
    }
}
