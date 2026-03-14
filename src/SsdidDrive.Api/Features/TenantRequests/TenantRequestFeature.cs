namespace SsdidDrive.Api.Features.TenantRequests;

public static class TenantRequestFeature
{
    public static void MapTenantRequestFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/tenant-requests")
            .WithTags("Tenant Requests");

        SubmitRequest.Map(group);
    }
}
