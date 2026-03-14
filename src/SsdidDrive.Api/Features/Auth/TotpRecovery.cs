using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpRecovery
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/recovery", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        IEmailService emailService,
        ILogger<Request> logger,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("No account with this email").ToProblemResult();

        if (!user.TotpEnabled)
            return AppError.BadRequest("TOTP is not enabled for this account").ToProblemResult();

        var code = await otpService.GenerateAsync(email, "recovery", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send recovery OTP to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Recovery code sent to your email" });
    }
}
