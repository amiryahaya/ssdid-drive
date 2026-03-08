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

        // SSE endpoint for real-time challenge completion (mapped outside the group
        // because it needs its own path prefix, not nested under the group)
        routes.MapAuthEvents();
    }
}
