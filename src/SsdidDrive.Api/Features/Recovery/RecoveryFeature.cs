namespace SsdidDrive.Api.Features.Recovery;

public static class RecoveryFeature
{
    public static void MapRecoveryFeature(this IEndpointRouteBuilder routes)
    {
        // Authenticated endpoints under /api/recovery
        var group = routes.MapGroup("/api/recovery").WithTags("Recovery");
        SetupRecovery.Map(group);
        GetRecoveryStatus.Map(group);
        DeleteRecoverySetup.Map(group);

        // Unauthenticated endpoints mapped directly on routes
        GetRecoveryShare.Map(routes);
        CompleteRecovery.Map(routes);
    }
}
