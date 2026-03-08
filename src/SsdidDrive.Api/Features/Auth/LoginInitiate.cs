using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class LoginInitiate
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/login/initiate", Handle);

    private static IResult Handle(
        SsdidIdentity identity,
        IConfiguration config)
    {
        // challengeId is a correlation ID for SSE session delivery only —
        // the wallet authenticates by presenting a VC, not by signing this challenge.
        var challengeId = Guid.NewGuid().ToString("N");
        var challenge = SsdidCrypto.GenerateChallenge();
        var serverSignature = identity.SignChallenge(challenge);

        var registryUrl = config["Ssdid:RegistryUrl"] ?? SsdidCrypto.DefaultRegistryUrl;
        var serviceUrl = config["Ssdid:ServiceUrl"] ?? "";

        var qrPayload = new
        {
            action = "login",
            service_url = serviceUrl,
            service_name = "ssdid-drive",
            challenge_id = challengeId,
            challenge,
            server_did = identity.Did,
            server_key_id = identity.KeyId,
            server_signature = serverSignature,
            registry_url = registryUrl
        };

        return Results.Ok(new
        {
            challenge_id = challengeId,
            qr_payload = qrPayload
        });
    }
}
