using SsdidDrive.Api.Common;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptInvitation
{
    public record Request(string? Token = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        Request req,
        CurrentUserAccessor accessor,
        InvitationAcceptanceService acceptanceService,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var result = await acceptanceService.AcceptAsync(
            user.Id,
            user.Email,
            invitationId: id,
            tokenProof: req.Token,
            ct: ct);

        return result.Match(
            ok => Results.Ok(new
            {
                id = ok.InvitationId,
                status = "accepted",
                tenant_id = ok.TenantId,
                role = ok.Role.ToString().ToLowerInvariant()
            }),
            err => err.ToProblemResult());
    }
}
