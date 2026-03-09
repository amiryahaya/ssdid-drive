namespace SsdidDrive.Api.Features.Shares;

public static class ShareFeature
{
    public static void MapShareFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/shares").WithTags("Shares");

        CreateShare.Map(group);
        GetShare.Map(group);
        ListCreatedShares.Map(group);
        ListReceivedShares.Map(group);
        UpdateSharePermission.Map(group);
        SetShareExpiry.Map(group);
        RevokeShare.Map(group);
    }
}
