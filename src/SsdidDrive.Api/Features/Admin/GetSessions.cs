using Ssdid.Sdk.Server.Session;

namespace SsdidDrive.Api.Features.Admin;

public static class GetSessions
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/sessions", Handle);

    private static IResult Handle(ISessionStore sessionStore)
    {
        return Results.Ok(new
        {
            active_sessions = sessionStore.ActiveSessionCount,
            active_challenges = sessionStore.ActiveChallengeCount
        });
    }
}
