using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcAuthorize
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/authorize", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static IResult Handle(
        string provider,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger)
    {
        var stateToken = Convert.ToBase64String(
            System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));

        var result = exchanger.GetAuthorizationUrl(provider, stateToken);
        if (result is null)
            return AppError.BadRequest($"OIDC provider '{provider}' is not supported or not configured").ToProblemResult();

        var (url, state, codeVerifier) = result.Value;

        // Store state → (codeVerifier, provider) mapping via challenge store (consumed on callback)
        sessionStore.CreateChallenge("oidc", stateToken, codeVerifier, provider);

        return Results.Redirect(url);
    }
}
