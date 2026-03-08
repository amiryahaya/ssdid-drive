using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Users;

public static class GetProfile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/me", Handle);

    private static IResult Handle(CurrentUserAccessor accessor)
    {
        var user = accessor.User!;
        return Results.Ok(new
        {
            user.Id,
            user.Did,
            user.DisplayName,
            user.Email,
            status = user.Status.ToString().ToLowerInvariant(),
            user.CreatedAt
        });
    }
}
