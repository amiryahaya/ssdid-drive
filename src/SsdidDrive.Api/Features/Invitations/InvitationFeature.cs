namespace SsdidDrive.Api.Features.Invitations;

public static class InvitationFeature
{
    public static void MapInvitationFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/invitations").WithTags("Invitations");

        CreateInvitation.Map(group);
        ListInvitations.Map(group);
        AcceptInvitation.Map(group);
        DeclineInvitation.Map(group);
        RevokeInvitation.Map(group);
        GetInvitationByToken.Map(group);
        AcceptWithWallet.Map(group);
    }
}
