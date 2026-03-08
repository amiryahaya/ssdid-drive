using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class Register
{
    public record Request(string Did, string KeyId);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/register", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth)
    {
        if (string.IsNullOrWhiteSpace(req.Did) || !req.Did.StartsWith("did:ssdid:") || req.Did.Length > 256)
            return AppError.BadRequest("Invalid DID format (expected did:ssdid:*, max 256 chars)").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyId) || req.KeyId.Length > 512)
            return AppError.BadRequest("Invalid KeyId (required, max 512 chars)").ToProblemResult();

        var result = await auth.HandleRegister(req.Did, req.KeyId);
        return result.Match(
            ok => Results.Ok(ok),
            err => err.ToProblemResult());
    }
}
