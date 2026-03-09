using SsdidDrive.Api.Common;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Credentials;

public static class BeginAddCredential
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/webauthn/begin", Handle);

    private static IResult Handle(CurrentUserAccessor accessor, WebAuthnChallengeStore challengeStore)
    {
        var user = accessor.User!;

        var challenge = challengeStore.CreateChallenge(user.Id);

        return Results.Ok(new
        {
            challenge,
            rp = new { name = "SSDID Drive", id = "drive.ssdid.my" },
            user = new
            {
                id = Convert.ToBase64String(user.Id.ToByteArray()),
                name = user.Did,
                display_name = user.DisplayName ?? user.Did
            },
            pub_key_cred_params = new[] { new { type = "public-key", alg = -7 } },
            timeout = 60000,
            attestation = "none",
            authenticator_selection = new { user_verification = "preferred" }
        });
    }
}
