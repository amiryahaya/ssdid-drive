using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Auth;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Auth;

public static class Authenticate
{
    public record Request(JsonElement Credential, string? ChallengeId = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/authenticate", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth, AppDbContext db, ISseNotificationBus sseBus, HttpContext httpContext)
    {
        // Step 1: Verify the credential (signature + revocation check)
        var verifyResult = await auth.VerifyCredential(req.Credential);

        // Step 1b: Explicit expiration enforcement (defense-in-depth)
        if (req.Credential.TryGetProperty("expirationDate", out var expEl))
        {
            var expStr = expEl.GetString();
            if (expStr is not null &&
                DateTimeOffset.TryParse(expStr, null, System.Globalization.DateTimeStyles.RoundtripKind, out var exp) &&
                exp < DateTimeOffset.UtcNow)
            {
                return Results.Problem(
                    statusCode: 401,
                    title: "Credential expired",
                    detail: $"Credential expired at {expStr}");
            }
        }

        return await verifyResult.Match(
            async did =>
            {
                // Step 2: Confirm user exists in DB
                var user = await db.Users
                    .Include(u => u.UserTenants)
                        .ThenInclude(ut => ut.Tenant)
                    .FirstOrDefaultAsync(u => u.Did == did);

                if (user is null)
                    return AppError.NotFound("No account linked to this DID").ToProblemResult();

                // Step 3: Create session with device binding
                var deviceFp = DeviceFingerprint.Compute(
                    httpContext.Request.Headers.UserAgent.FirstOrDefault(),
                    httpContext.Request.Headers[DeviceFingerprint.DeviceIdHeader].FirstOrDefault());
                var sessionResult = auth.CreateAuthenticatedSession(did, deviceFp);
                return await sessionResult.Match(
                    async ok =>
                    {
                        try
                        {
                            user.LastLoginAt = DateTimeOffset.UtcNow;
                            await db.SaveChangesAsync();
                        }
                        catch (Exception)
                        {
                            auth.RevokeSession(ok.SessionToken);
                            throw;
                        }

                        // Notify any SSE waiter that the challenge has been completed
                        if (!string.IsNullOrWhiteSpace(req.ChallengeId))
                            sseBus.NotifyCompletion(req.ChallengeId, ok.SessionToken);

                        var tenants = user.UserTenants.Select(ut => new
                        {
                            id = ut.TenantId,
                            name = ut.Tenant.Name,
                            slug = ut.Tenant.Slug,
                            role = ut.Role.ToString().ToLowerInvariant()
                        });

                        return Results.Ok(new
                        {
                            session_token = ok.SessionToken,
                            did = ok.Did,
                            server_did = ok.ServerDid,
                            server_key_id = ok.ServerKeyId,
                            server_signature = ok.ServerSignature,
                            user = new { user.Id, user.Did, user.DisplayName, status = user.Status.ToString().ToLowerInvariant() },
                            tenants
                        });
                    },
                    err => Task.FromResult(err.ToProblemResult()));
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
