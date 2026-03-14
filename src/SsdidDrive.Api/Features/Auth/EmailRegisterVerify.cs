using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailRegisterVerify
{
    public record Request(string Email, string Code, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/register/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        ISessionStore sessionStore,
        AuditService auditService,
        InvitationAcceptanceService acceptanceService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.BadRequest("Invitation token is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Verify OTP before doing anything else
        if (!await otpService.VerifyAsync(email, "register", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired verification code").ToProblemResult();

        // Look up invitation to get tenantId for the new user
        var invitationToken = req.InvitationToken!.Trim();
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => (i.Token == invitationToken || i.ShortCode == invitationToken)
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // Create user
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            EmailVerified = true,
            Status = UserStatus.Active,
            TenantId = invitation.TenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        db.Users.Add(user);

        db.Logins.Add(new Login
        {
            AccountId = user.Id,
            Provider = LoginProvider.Email,
            ProviderSubject = email,
        });

        await db.SaveChangesAsync(ct);

        // Delegate invitation acceptance to shared service
        var result = await acceptanceService.AcceptAsync(
            user.Id,
            email,
            token: invitationToken,
            ct: ct);

        return result.Match(
            ok =>
            {
                var token = sessionStore.CreateSession(user.Id.ToString());
                if (token is null)
                    return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

                // Audit log
                _ = auditService.LogAsync(user.Id, "auth.register.email", "user", user.Id, null, ct);

                return Results.Ok(new
                {
                    token,
                    account_id = user.Id,
                    email = user.Email,
                    requires_totp_setup = true,
                });
            },
            err => err.ToProblemResult());
    }
}
