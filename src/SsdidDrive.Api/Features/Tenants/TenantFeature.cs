namespace SsdidDrive.Api.Features.Tenants;

public static class TenantFeature
{
    public static void MapTenantFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/tenants").WithTags("Tenants");

        ListMembers.Map(group);
        UpdateMemberRole.Map(group);
        RemoveMember.Map(group);
    }
}
