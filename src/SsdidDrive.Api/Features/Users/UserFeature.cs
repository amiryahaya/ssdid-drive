namespace SsdidDrive.Api.Features.Users;

public static class UserFeature
{
    public static void MapUserFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api").WithTags("Users");

        GetProfile.Map(group);
        UpdateProfile.Map(group);
        GetKeys.Map(group);
        UpdateKeys.Map(group);
        ListTenantUsers.Map(group);
        GetPublicKey.Map(group);
        PublishKemKey.Map(group);
        GetKemPublicKey.Map(group);
    }
}
