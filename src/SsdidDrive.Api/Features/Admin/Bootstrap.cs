using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class Bootstrap
{
    public record SetupRequest(string Email, string DisplayName);
    public record ConfirmRequest(string Email, string Code);

    public static void MapBootstrap(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/admin/bootstrap")
            .WithTags("Bootstrap");

        group.MapGet("/status", HandleStatus)
            .WithMetadata(new SsdidPublicAttribute());

        group.MapPost("/setup", HandleSetup)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

        group.MapPost("/confirm", HandleConfirm)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth-totp");
    }

    private static async Task<IResult> HandleStatus(AppDbContext db, CancellationToken ct)
    {
        var hasSuperAdmin = await db.Users
            .AnyAsync(u => u.SystemRole == SystemRole.SuperAdmin && u.Status == UserStatus.Active, ct);

        return Results.Ok(new { required = !hasSuperAdmin });
    }

    private static async Task<IResult> HandleSetup(
        SetupRequest req,
        AppDbContext db,
        TotpService totpService,
        TotpEncryption totpEncryption,
        CancellationToken ct)
    {
        // Guard: only works when no SuperAdmin exists
        var hasSuperAdmin = await db.Users
            .AnyAsync(u => u.SystemRole == SystemRole.SuperAdmin && u.Status == UserStatus.Active, ct);
        if (hasSuperAdmin)
            return AppError.Forbidden("Bootstrap is no longer available — a SuperAdmin already exists").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.DisplayName))
            return AppError.BadRequest("Display name is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Check if user with this email already exists
        var existingUser = await db.Users.FirstOrDefaultAsync(u => u.Email == email, ct);
        if (existingUser is not null)
            return AppError.Conflict("A user with this email already exists").ToProblemResult();

        // Create SuperAdmin user with TOTP secret (not yet enabled)
        var secret = totpService.GenerateSecret();
        var uri = totpService.GenerateOtpAuthUri(secret, email);

        var user = new User
        {
            DisplayName = req.DisplayName.Trim(),
            Email = email,
            Status = UserStatus.Active,
            SystemRole = SystemRole.SuperAdmin,
            EmailVerified = true,
            TotpSecret = totpEncryption.Encrypt(secret),
            TotpEnabled = false,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        db.Users.Add(user);
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            secret,
            otpauth_uri = uri,
            email,
        });
    }

    private static async Task<IResult> HandleConfirm(
        ConfirmRequest req,
        AppDbContext db,
        TotpService totpService,
        TotpEncryption totpEncryption,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        // Guard: only works when no active SuperAdmin with TOTP enabled
        var hasSuperAdmin = await db.Users
            .AnyAsync(u => u.SystemRole == SystemRole.SuperAdmin
                && u.Status == UserStatus.Active
                && u.TotpEnabled, ct);
        if (hasSuperAdmin)
            return AppError.Forbidden("Bootstrap is no longer available").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();
        var user = await db.Users.FirstOrDefaultAsync(
            u => u.Email == email && u.SystemRole == SystemRole.SuperAdmin, ct);

        if (user is null)
            return AppError.NotFound("Bootstrap user not found — call /setup first").ToProblemResult();

        if (string.IsNullOrEmpty(user.TotpSecret))
            return AppError.BadRequest("TOTP not set up — call /setup first").ToProblemResult();

        var decryptedSecret = totpEncryption.Decrypt(user.TotpSecret);
        if (!totpService.VerifyCode(decryptedSecret, req.Code))
            return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();

        var backupCodes = totpService.GenerateBackupCodes();

        user.TotpEnabled = true;
        user.BackupCodes = totpEncryption.Encrypt(
            System.Text.Json.JsonSerializer.Serialize(backupCodes));
        user.LastLoginAt = DateTimeOffset.UtcNow;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(user.Id, "admin.bootstrap", "user", user.Id,
            $"SuperAdmin bootstrapped: {email}", ct);

        return Results.Ok(new
        {
            token,
            backup_codes = backupCodes,
            account_id = user.Id,
            display_name = user.DisplayName,
            email = user.Email,
        });
    }
}
