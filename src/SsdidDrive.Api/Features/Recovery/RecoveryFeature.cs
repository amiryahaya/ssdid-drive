namespace SsdidDrive.Api.Features.Recovery;

public static class RecoveryFeature
{
    public static void MapRecoveryFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/recovery").WithTags("Recovery");

        SetupRecovery.Map(group);
        DistributeShare.Map(group);
        ListTrusteeShares.Map(group);
        AcceptRecoveryShare.Map(group);
        RejectRecoveryShare.Map(group);
        InitiateRecovery.Map(group);
        ApproveRecovery.Map(group);
        GetRecoveryStatus.Map(group);
        GetRecoveryRequest.Map(group);
    }
}
