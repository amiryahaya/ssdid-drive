using System.Net.Mail;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class CreateInvitation
{
    public record Request(string? Email, string? Role, string? Message);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, EmailService? emailService, CancellationToken ct)
    {
        var user = accessor.User!;

        // Validate email format if provided
        if (!string.IsNullOrWhiteSpace(req.Email) && !MailAddress.TryCreate(req.Email, out _))
            return AppError.BadRequest("Invalid email address format").ToProblemResult();

        // Cap message length
        if (req.Message is { Length: > 500 })
            return AppError.BadRequest("Message must be 500 characters or fewer").ToProblemResult();

        if (user.TenantId is null)
            return AppError.BadRequest("You must belong to a tenant to create invitations").ToProblemResult();

        // Check caller is Admin or Owner
        var userTenant = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == user.Id && ut.TenantId == user.TenantId, ct);

        if (userTenant is null || userTenant.Role == TenantRole.Member)
            return AppError.Forbidden("Only admins or owners can create invitations").ToProblemResult();

        // Parse role
        var role = req.Role?.ToLowerInvariant() switch
        {
            "member" or null => TenantRole.Member,
            "admin" => TenantRole.Admin,
            _ => (TenantRole?)null
        };

        if (role is null)
            return AppError.BadRequest("Role must be 'member' or 'admin'").ToProblemResult();

        // Role constraint: Admin can only invite Members
        if (userTenant.Role == TenantRole.Admin && role != TenantRole.Member)
            return AppError.Forbidden("Admins can only invite members").ToProblemResult();

        var now = DateTimeOffset.UtcNow;
        var token = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');

        // Generate short code: SLUG-XXXX (tenant slug prefix + 4 random alphanumeric chars)
        var tenant = await db.Tenants.FindAsync([user.TenantId.Value], ct);
        var shortCode = await GenerateShortCode(db, tenant!.Slug, ct);

        // Resolve email to user ID if the user already exists
        Guid? invitedUserId = null;
        if (!string.IsNullOrWhiteSpace(req.Email))
        {
            var invitedUser = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email, ct);
            invitedUserId = invitedUser?.Id;
        }

        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = user.TenantId.Value,
            InvitedById = user.Id,
            InvitedUserId = invitedUserId,
            Email = req.Email,
            Role = role.Value,
            Status = InvitationStatus.Pending,
            Token = token,
            ShortCode = shortCode,
            Message = req.Message,
            ExpiresAt = now.AddDays(7),
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Invitations.Add(invitation);

        if (invitedUserId is not null)
        {
            await notifications.CreateAsync(
                invitedUserId.Value,
                "invitation_received",
                "New Invitation",
                "You've been invited to join a tenant",
                actionType: "invitation",
                actionResourceId: invitation.Id.ToString(),
                ct: ct);
        }

        await db.SaveChangesAsync(ct);

        // Send invitation email (fire-and-forget, won't block the response)
        if (emailService is not null && !string.IsNullOrWhiteSpace(req.Email))
        {
            var email = req.Email;
            var tenantName = tenant!.Name;
            var roleName = role.Value.ToString().ToLowerInvariant();
            var msg = req.Message;
            _ = Task.Run(() => emailService.SendInvitationAsync(email, tenantName, roleName, shortCode, msg));
        }

        return Results.Created($"/api/invitations/{invitation.Id}", new
        {
            invitation.Id,
            invitation.TenantId,
            invitation.InvitedById,
            invitation.Email,
            invitation.InvitedUserId,
            Role = invitation.Role.ToString().ToLowerInvariant(),
            Status = invitation.Status.ToString().ToLowerInvariant(),
            invitation.ShortCode,
            invitation.Message,
            invitation.ExpiresAt,
            invitation.CreatedAt
        });
    }

    private static async Task<string> GenerateShortCode(AppDbContext db, string tenantSlug, CancellationToken ct)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No 0/O/1/I to avoid confusion
        var prefix = tenantSlug.Split('-')[0].ToUpperInvariant();
        if (prefix.Length > 6) prefix = prefix[..6];

        for (var attempt = 0; attempt < 10; attempt++)
        {
            var suffix = new string(Enumerable.Range(0, 4)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());

            var code = $"{prefix}-{suffix}";

            if (!await db.Invitations.AnyAsync(i => i.ShortCode == code, ct))
                return code;
        }

        // Fallback: longer suffix with uniqueness check
        for (var fallbackAttempt = 0; fallbackAttempt < 5; fallbackAttempt++)
        {
            var fallbackSuffix = new string(Enumerable.Range(0, 6)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());

            var fallbackCode = $"{prefix}-{fallbackSuffix}";
            if (!await db.Invitations.AnyAsync(i => i.ShortCode == fallbackCode, ct))
                return fallbackCode;
        }

        throw new InvalidOperationException("Short code space exhausted for this tenant; please retry");
    }
}
