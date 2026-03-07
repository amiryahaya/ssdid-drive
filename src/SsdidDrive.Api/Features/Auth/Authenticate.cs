using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class Authenticate
{
    public record Request(JsonElement Credential, string? ChallengeId = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/authenticate", Handle);

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth, AppDbContext db, SessionStore sessionStore)
    {
        var result = auth.HandleAuthenticate(req.Credential);
        return await result.Match(
            async ok =>
            {
                var user = await db.Users
                    .Include(u => u.UserTenants)
                        .ThenInclude(ut => ut.Tenant)
                    .FirstOrDefaultAsync(u => u.Did == ok.Did);

                if (user is null)
                {
                    // Revoke the orphaned session created by HandleAuthenticate
                    auth.RevokeSession(ok.SessionToken);
                    return AppError.NotFound("No account linked to this DID").ToProblemResult();
                }

                try
                {
                    user.LastLoginAt = DateTimeOffset.UtcNow;
                    await db.SaveChangesAsync();
                }
                catch
                {
                    auth.RevokeSession(ok.SessionToken);
                    throw;
                }

                // Notify any SSE waiter that the challenge has been completed
                if (!string.IsNullOrWhiteSpace(req.ChallengeId))
                    sessionStore.NotifyCompletion(req.ChallengeId, ok.SessionToken);

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
            err => Task.FromResult(err.ToProblemResult()));
    }
}
