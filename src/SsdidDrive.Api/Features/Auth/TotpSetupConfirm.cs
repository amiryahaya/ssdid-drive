using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpSetupConfirm
{
    public record Request(string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/setup/confirm", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        TotpService totpService,
        TotpEncryption totpEncryption,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("TOTP code is required").ToProblemResult();

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        if (string.IsNullOrEmpty(user.TotpSecret))
            return AppError.BadRequest("Call /totp/setup first").ToProblemResult();

        if (user.TotpEnabled)
            return AppError.Conflict("TOTP is already enabled").ToProblemResult();

        // Decrypt secret for verification
        var decryptedSecret = totpEncryption.Decrypt(user.TotpSecret);
        if (!totpService.VerifyCode(decryptedSecret, req.Code))
            return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();

        var backupCodes = totpService.GenerateBackupCodes();

        user.TotpEnabled = true;
        user.BackupCodes = totpEncryption.Encrypt(System.Text.Json.JsonSerializer.Serialize(backupCodes));
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.totp.setup", "user", accessor.UserId, null, ct);

        return Results.Ok(new
        {
            totp_enabled = true,
            backup_codes = backupCodes,
        });
    }
}
