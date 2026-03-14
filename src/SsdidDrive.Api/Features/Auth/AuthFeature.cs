namespace SsdidDrive.Api.Features.Auth;

public static class AuthFeature
{
    public static void MapAuthFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/auth/ssdid")
            .WithTags("Authentication")
            .RequireRateLimiting("auth");

        ServerInfo.Map(group);
        Register.Map(group);
        RegisterVerify.Map(group);
        Authenticate.Map(group);
        Logout.Map(group);
        LoginInitiate.Map(group);

        // Standard SSDID protocol routes at /api/* so that SSDID Wallet
        // (which uses the standard paths) can reach them without knowing
        // about Drive's internal /api/auth/ssdid/* prefix.
        var standardGroup = routes.MapGroup("/api")
            .WithTags("Authentication (SSDID Protocol)")
            .RequireRateLimiting("auth");

        Register.Map(standardGroup);
        RegisterVerify.Map(standardGroup);
        Authenticate.Map(standardGroup);

        // SSE endpoint for real-time challenge completion (mapped outside the group
        // because it needs its own path prefix, not nested under the group)
        routes.MapAuthEvents();

        // New auth endpoints (email + TOTP + OIDC)
        var auth = routes.MapGroup("/api/auth")
            .WithTags("Authentication");

        EmailRegister.Map(auth);
        EmailRegisterVerify.Map(auth);
        TotpSetup.Map(auth);
        TotpSetupConfirm.Map(auth);
        EmailLogin.Map(auth);
        TotpVerify.Map(auth);
        OidcVerify.Map(auth);
    }
}
