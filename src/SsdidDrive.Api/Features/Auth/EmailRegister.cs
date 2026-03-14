using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailRegister
{
    public record Request(string Email, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/register", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth-otp");

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

        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.BadRequest("Invitation token is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var invitationToken = req.InvitationToken!.Trim();
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => (i.Token == invitationToken || i.ShortCode == invitationToken)
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        var existingUser = await db.Users
            .FirstOrDefaultAsync(u => u.Email == email, ct);

        if (existingUser is not null)
            return AppError.Conflict("An account with this email already exists").ToProblemResult();

        var code = await otpService.GenerateAsync(email, "register", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send OTP email to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Verification code sent to your email" });
    }
}
