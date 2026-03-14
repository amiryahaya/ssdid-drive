using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Users;

public static class GetProfile
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/me", Handle);

    private static IResult Handle(CurrentUserAccessor accessor)
    {
        var user = accessor.User!;

        // Fields are editable only when empty (not populated by a login provider)
        var editableFields = new List<string>();
        if (string.IsNullOrWhiteSpace(user.DisplayName)) editableFields.Add("display_name");
        if (string.IsNullOrWhiteSpace(user.Email)) editableFields.Add("email");

        return Results.Ok(new
        {
            user.Id,
            user.Did,
            user.DisplayName,
            user.Email,
            status = user.Status.ToString().ToLowerInvariant(),
            system_role = user.SystemRole?.ToString(),
            user.CreatedAt,
            editable_fields = editableFields
        });
    }
}
