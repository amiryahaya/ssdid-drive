using System.Security.Cryptography;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcAuthorize
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/authorize", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static IResult Handle(
        string provider,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger)
    {
        // Use hex encoding — safe in query strings without escaping
        var stateToken = RandomNumberGenerator.GetHexString(64, lowercase: true);

        var result = exchanger.GetAuthorizationUrl(provider, stateToken);
        if (result is null)
            return AppError.BadRequest($"OIDC provider '{provider}' is not supported or not configured").ToProblemResult();

        var (url, state, codeVerifier) = result.Value;

        // Store state → (codeVerifier, provider) mapping via challenge store (consumed on callback)
        sessionStore.CreateChallenge("oidc", state, codeVerifier, provider);

        return Results.Redirect(url);
    }
}
