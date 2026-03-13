namespace SsdidDrive.Api.Features.Activity;

public static class ActivityFeature
{
    public static void MapActivityFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/activity")
            .WithTags("Activity");

        ListActivity.Map(group);
        ListResourceActivity.Map(group);
        ListAdminActivity.Map(group);
    }
}
