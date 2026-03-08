using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class Authenticate
{
    public record Request(JsonElement Credential, string? ChallengeId = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/authenticate", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth, AppDbContext db, ISseNotificationBus sseBus)
    {
        // Step 1: Verify the credential (no session created yet)
        var verifyResult = auth.VerifyCredential(req.Credential);
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

                // Step 3: Create session only after user is confirmed
                var sessionResult = auth.CreateAuthenticatedSession(did);
                return sessionResult.Match(
                    ok =>
                    {
                        try
                        {
                            user.LastLoginAt = DateTimeOffset.UtcNow;
                            db.SaveChanges();
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
                            server_signature = ok.ServerSignature,
                            user = new { user.Id, user.Did, user.DisplayName, status = user.Status.ToString().ToLowerInvariant() },
                            tenants
                        });
                    },
                    err => err.ToProblemResult());
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
