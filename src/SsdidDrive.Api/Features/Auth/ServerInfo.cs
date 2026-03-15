using Ssdid.Sdk.Server.Encoding;
using Ssdid.Sdk.Server.Identity;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Auth;

public static class ServerInfo
{
    public record Response(string ServerDid, string ServerKeyId, string ServiceName, string RegistryUrl);

    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/server-info", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static IResult Handle(SsdidIdentity identity, IConfiguration config)
    {
        var registryUrl = config["Ssdid:RegistryUrl"] ?? SsdidEncoding.DefaultRegistryUrl;
        return Results.Ok(new Response(identity.Did, identity.KeyId, "drive", registryUrl));
    }
}
