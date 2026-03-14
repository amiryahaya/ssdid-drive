using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpSetup
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/setup", Handle);

    private static async Task<IResult> Handle(
        CurrentUserAccessor accessor,
        AppDbContext db,
        TotpService totpService,
        TotpEncryption totpEncryption,
        CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        if (user.TotpEnabled)
            return AppError.Conflict("TOTP is already enabled").ToProblemResult();

        var secret = totpService.GenerateSecret();
        var uri = totpService.GenerateOtpAuthUri(secret, user.Email ?? "unknown");

        // Store encrypted secret (not yet enabled until confirmed)
        user.TotpSecret = totpEncryption.Encrypt(secret);
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            secret,       // plaintext for the authenticator app
            otpauth_uri = uri,
        });
    }
}
