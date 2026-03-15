using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Auth;

public static class Logout
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logout", Handle);

    private static IResult Handle(CurrentUserAccessor accessor, ISessionStore store)
    {
        if (accessor.SessionToken is not null)
            store.DeleteSession(accessor.SessionToken);
        return Results.NoContent();
    }
}
