using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkEmail
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/email", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OtpService otpService,
        IEmailService emailService,
        ILogger<Request> logger,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var existing = await db.Logins
            .AnyAsync(l => l.Provider == LoginProvider.Email
                && l.ProviderSubject == email
                && l.AccountId != accessor.UserId, ct);

        if (existing)
            return AppError.Conflict("This email is already linked to another account").ToProblemResult();

        var alreadyLinked = await db.Logins
            .AnyAsync(l => l.Provider == LoginProvider.Email
                && l.AccountId == accessor.UserId, ct);

        if (alreadyLinked)
            return AppError.Conflict("An email login is already linked to this account").ToProblemResult();

        var code = await otpService.GenerateAsync(email, "link", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send link OTP to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Verification code sent" });
    }
}
