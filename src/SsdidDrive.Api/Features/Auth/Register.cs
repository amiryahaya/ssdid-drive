using Ssdid.Sdk.Server;
using Ssdid.Sdk.Server.Auth;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Auth;

public static class Register
{
    public record Request(string Did, string KeyId);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/register", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth)
    {
        if (!SsdidDid.IsValid(req.Did))
            return AppError.BadRequest("Invalid DID format (expected did:ssdid:<base64url>, 22-128 chars)").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyId) || req.KeyId.Length > 512)
            return AppError.BadRequest("Invalid KeyId (required, max 512 chars)").ToProblemResult();

        var result = await auth.HandleRegister(req.Did, req.KeyId);
        return result.Match(
            ok => Results.Ok(ok),
            err => err.ToProblemResult());
    }
}
