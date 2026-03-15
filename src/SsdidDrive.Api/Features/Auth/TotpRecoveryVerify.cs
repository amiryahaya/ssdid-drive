using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpRecoveryVerify
{
    public record Request(string Email, string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/recovery/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth-recovery");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        if (!await otpService.VerifyAsync(email, "recovery", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired recovery code").ToProblemResult();

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        // Disable old TOTP and invalidate backup codes
        user.TotpEnabled = false;
        user.TotpSecret = null;
        user.BackupCodes = null;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // Revoke all existing sessions for this account
        sessionStore.InvalidateSessionsForDid(user.Id.ToString());
        if (!string.IsNullOrEmpty(user.Did))
            sessionStore.InvalidateSessionsForDid(user.Did);

        await auditService.LogAsync(user.Id, "auth.totp.reset", "user", user.Id, null, ct);
        await auditService.LogAsync(user.Id, "auth.sessions.revoked", "user", user.Id,
            "TOTP recovery", ct);

        // Create new session so user can set up TOTP again
        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        return Results.Ok(new
        {
            token,
            account_id = user.Id,
            totp_disabled = true,
            requires_totp_setup = true,
        });
    }
}
