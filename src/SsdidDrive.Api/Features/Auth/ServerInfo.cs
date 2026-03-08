using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class ServerInfo
{
    public record Response(string ServerDid, string ServerKeyId, string ServiceName, string RegistryUrl);

    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/server-info", Handle);

    private static IResult Handle(SsdidIdentity identity, IConfiguration config)
    {
        var registryUrl = config["Ssdid:RegistryUrl"] ?? SsdidCrypto.DefaultRegistryUrl;
        return Results.Ok(new Response(identity.Did, identity.KeyId, "drive", registryUrl));
    }
}
