using Ssdid.Sdk.Server.Encoding;
using Ssdid.Sdk.Server.Identity;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Auth;

public static class LoginInitiate
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/login/initiate", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static IResult Handle(
        SsdidIdentity identity,
        ISseNotificationBus sseBus,
        IConfiguration config)
    {
        // challengeId is a correlation ID for SSE session delivery only —
        // the wallet authenticates by presenting a VC, not by signing this challenge.
        var challengeId = Guid.NewGuid().ToString("N");
        var challenge = SsdidEncoding.GenerateChallenge();
        var serverSignature = identity.SignChallenge(challenge);

        // Generate a subscriber secret so only the initiator can listen on SSE
        var subscriberSecret = sseBus.CreateSubscriberSecret(challengeId);

        var registryUrl = config["Ssdid:RegistryUrl"] ?? SsdidEncoding.DefaultRegistryUrl;
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
            registry_url = registryUrl,
            requested_claims = new
            {
                required = new[] { "name" },
                optional = new[] { "email" }
            }
        };

        return Results.Ok(new
        {
            challenge_id = challengeId,
            subscriber_secret = subscriberSecret,
            qr_payload = qrPayload
        });
    }
}
