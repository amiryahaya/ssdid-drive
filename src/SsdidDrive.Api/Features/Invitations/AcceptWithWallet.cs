using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Auth;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptWithWallet
{
    public record Request(JsonElement Credential, string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/token/{token}/accept-with-wallet", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        string token,
        Request req,
        AppDbContext db,
        SsdidAuthService auth,
        InvitationAcceptanceService acceptanceService,
        HttpContext httpContext,
        CancellationToken ct)
    {
        // 1. Verify credential first (cheap to fail fast)
        var verifyResult = await auth.VerifyCredential(req.Credential);
        return await verifyResult.Match(
            async did =>
            {
                // 2. Find or create user
                var user = await db.Users
                    .FirstOrDefaultAsync(u => u.Did == did, ct);

                var isNewUser = user is null;
                if (isNewUser)
                {
                    // Look up invitation to get tenantId for new user's primary tenant
                    var invitation = await db.Invitations
                        .FirstOrDefaultAsync(i => i.Token == token || i.ShortCode == token, ct);

                    if (invitation is null)
                        return AppError.NotFound("Invitation not found").ToProblemResult();

                    user = new User
                    {
                        Id = Guid.NewGuid(),
                        Did = did,
                        Email = req.Email?.Trim().ToLowerInvariant(),
                        DisplayName = null,
                        Status = UserStatus.Active,
                        TenantId = invitation.TenantId,
                        CreatedAt = DateTimeOffset.UtcNow,
                        UpdatedAt = DateTimeOffset.UtcNow
                    };
                    db.Users.Add(user);
                    try
                    {
                        await db.SaveChangesAsync(ct);
                    }
                    catch (DbUpdateException)
                    {
                        db.ChangeTracker.Clear();
                        user = await db.Users.FirstAsync(u => u.Did == did, ct);
                        isNewUser = false;
                    }
                }

                // 3. Delegate invitation acceptance to shared service
                var result = await acceptanceService.AcceptAsync(
                    user!.Id,
                    req.Email,
                    token: token,
                    acceptedByDid: did,
                    ct: ct);

                return result.Match(
                    ok =>
                    {
                        // 4. Create session with device binding
                        var deviceFp = Ssdid.Sdk.Server.Session.DeviceFingerprint.Compute(
                            httpContext.Request.Headers.UserAgent.FirstOrDefault(),
                            httpContext.Request.Headers[Ssdid.Sdk.Server.Session.DeviceFingerprint.DeviceIdHeader].FirstOrDefault());
                        var sessionResult = auth.CreateAuthenticatedSession(did, deviceFp);
                        return sessionResult.Match(
                            session => Results.Ok(new
                            {
                                session_token = session.SessionToken,
                                did = session.Did,
                                server_did = session.ServerDid,
                                server_key_id = session.ServerKeyId,
                                server_signature = session.ServerSignature,
                                user = new
                                {
                                    user!.Id,
                                    user.Did,
                                    display_name = user.DisplayName,
                                    status = user.Status.ToString().ToLowerInvariant()
                                },
                                tenant = new
                                {
                                    id = ok.TenantId,
                                    name = ok.TenantName,
                                    slug = ok.TenantSlug,
                                    role = ok.Role.ToString().ToLowerInvariant()
                                }
                            }),
                            err => err.ToProblemResult());
                    },
                    err => err.ToProblemResult());
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
