using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkEmailVerify
{
    public record Request(string Email, string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/email/verify", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OtpService otpService,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        if (!await otpService.VerifyAsync(email, "link", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired verification code").ToProblemResult();

        db.Logins.Add(new Login
        {
            AccountId = accessor.UserId,
            Provider = LoginProvider.Email,
            ProviderSubject = email,
        });

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is not null)
        {
            user.Email = email;
            user.EmailVerified = true;
            user.UpdatedAt = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.linked", "login", null,
            "Provider: email", ct);

        return Results.Ok(new
        {
            linked = true,
            requires_totp_setup = user is not null && !user.TotpEnabled,
        });
    }
}
