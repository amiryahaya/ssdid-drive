using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class LoginInitiate
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/login/initiate", Handle);

    private static IResult Handle(
        SsdidIdentity identity,
        SessionStore sessionStore,
        IConfiguration config)
    {
        var challengeId = Guid.NewGuid().ToString("N");
        var challenge = SsdidCrypto.GenerateChallenge();
        var serverSignature = identity.SignChallenge(challenge);

        sessionStore.CreateChallenge(challengeId, "login", challenge, keyId: "");

        var registryUrl = config["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
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
