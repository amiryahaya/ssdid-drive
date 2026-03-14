using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpVerify
{
    /// <summary>
    /// Email+Code for email login flow, or SessionToken+Code for MFA session upgrade (OIDC).
    /// </summary>
    public record Request(string? Email, string Code, string? SessionToken = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth-totp");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        TotpService totpService,
        TotpEncryption totpEncryption,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Code is required").ToProblemResult();

        User? user;

        // Mode 1: MFA session upgrade — caller provides an mfa: prefixed session token
        if (!string.IsNullOrWhiteSpace(req.SessionToken))
        {
            var sessionValue = sessionStore.GetSession(req.SessionToken);
            if (sessionValue is null || !sessionValue.StartsWith("mfa:"))
                return AppError.Unauthorized("Invalid or expired MFA session").ToProblemResult();

            var userIdStr = sessionValue["mfa:".Length..];
            if (!Guid.TryParse(userIdStr, out var userId))
                return AppError.Unauthorized("Invalid MFA session").ToProblemResult();

            user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId && u.Status == UserStatus.Active, ct);
        }
        // Mode 2: Email login flow
        else if (!string.IsNullOrWhiteSpace(req.Email))
        {
            var email = req.Email.Trim().ToLowerInvariant();
            user = await db.Users
                .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);
        }
        else
        {
            return AppError.BadRequest("Email or session token is required").ToProblemResult();
        }

        if (user is null)
            return AppError.Unauthorized("Invalid credentials").ToProblemResult();

        if (!user.TotpEnabled || string.IsNullOrEmpty(user.TotpSecret))
            return AppError.BadRequest("TOTP is not set up for this account").ToProblemResult();

        // Decrypt secret
        var decryptedSecret = totpEncryption.Decrypt(user.TotpSecret);
        bool valid = totpService.VerifyCode(decryptedSecret, req.Code);

        // If TOTP failed, try backup code
        string? updatedBackupCodes = null;
        if (!valid && !string.IsNullOrEmpty(user.BackupCodes))
        {
            var decryptedCodes = totpEncryption.Decrypt(user.BackupCodes);
            var (backupValid, remaining) = totpService.VerifyBackupCode(decryptedCodes, req.Code);
            if (backupValid)
            {
                valid = true;
                updatedBackupCodes = remaining is not null ? totpEncryption.Encrypt(remaining) : null;
            }
        }

        if (!valid)
        {
            await auditService.LogAsync(Guid.Empty, "auth.login.failed", "user", user.Id,
                $"Failed TOTP for {user.Email ?? user.Id.ToString()}", ct);
            return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();
        }

        if (updatedBackupCodes is not null)
            user.BackupCodes = updatedBackupCodes;

        user.LastLoginAt = DateTimeOffset.UtcNow;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // If upgrading an MFA session, revoke the old restricted session first
        if (!string.IsNullOrWhiteSpace(req.SessionToken))
            sessionStore.DeleteSession(req.SessionToken);

        // Create a full (non-MFA) session
        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(user.Id,
            req.SessionToken is not null ? "auth.mfa.completed" : "auth.login.email",
            "user", user.Id, null, ct);

        return Results.Ok(new
        {
            token,
            account_id = user.Id,
            email = user.Email,
            display_name = user.DisplayName,
        });
    }
}
