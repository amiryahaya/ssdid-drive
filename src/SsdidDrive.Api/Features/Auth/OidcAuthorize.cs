using System.Security.Cryptography;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcAuthorize
{
    /// Allowed redirect_uri prefixes for OIDC callbacks.
    /// Each platform uses a different custom scheme.
    private static readonly string[] AllowedRedirectUriPrefixes =
    [
        "ssdid-drive://auth/callback",   // iOS
        "ssdiddrive://auth/callback",     // Android
    ];

    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/authorize", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static IResult Handle(
        string provider,
        string? redirect_uri,
        string? invitation_token,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger)
    {
        // SECURITY: Validate redirect_uri against allowlist to prevent open redirect
        if (redirect_uri is not null
            && !AllowedRedirectUriPrefixes.Any(p =>
                redirect_uri.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
        {
            return AppError.BadRequest("Invalid redirect_uri").ToProblemResult();
        }

        var stateToken = RandomNumberGenerator.GetHexString(64, lowercase: true);

        var result = exchanger.GetAuthorizationUrl(provider, stateToken);
        if (result is null)
            return AppError.BadRequest($"OIDC provider '{provider}' is not supported or not configured").ToProblemResult();

        var (url, state, codeVerifier) = result.Value;

        // 3-segment format: "codeVerifier|redirect_uri|invitation_token"
        var challengePayload = $"{codeVerifier}|{redirect_uri ?? ""}|{invitation_token ?? ""}";
        sessionStore.CreateChallenge("oidc", state, challengePayload, provider);

        return Results.Redirect(url);
    }
}
