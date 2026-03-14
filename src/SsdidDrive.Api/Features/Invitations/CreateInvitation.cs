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

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, IEmailService emailService, AuditService audit, CancellationToken ct)
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
        var token = InvitationHelper.GenerateToken();

        // Generate short code: SLUG-XXXX (tenant slug prefix + 4 random alphanumeric chars)
        var tenant = await db.Tenants.FindAsync([user.TenantId.Value], ct);
        var shortCode = await InvitationHelper.GenerateShortCode(db, tenant!.Slug, ct);

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

        // Send invitation email — capture success/failure for response
        bool emailSent = false;
        string? emailError = null;
        if (!string.IsNullOrWhiteSpace(req.Email))
        {
            try
            {
                await emailService.SendInvitationAsync(
                    req.Email, tenant!.Name, role.Value.ToString().ToLowerInvariant(), shortCode, req.Message);
                emailSent = true;
            }
            catch (Exception)
            {
                emailError = "Failed to send invitation email";
            }
        }

        // Audit log
        await audit.LogAsync(user.Id, "invitation.created", "Invitation", invitation.Id,
            $"Invited {req.Email ?? "(no email)"} as {role.Value.ToString().ToLowerInvariant()} to tenant {tenant!.Name}", ct);

        return Results.Created($"/api/invitations/{invitation.Id}", new
        {
            id = invitation.Id,
            tenant_id = invitation.TenantId,
            invited_by_id = invitation.InvitedById,
            email = invitation.Email,
            invited_user_id = invitation.InvitedUserId,
            role = invitation.Role.ToString().ToLowerInvariant(),
            status = invitation.Status.ToString().ToLowerInvariant(),
            token = invitation.Token,
            short_code = invitation.ShortCode,
            message = invitation.Message,
            email_sent = emailSent,
            email_error = emailError,
            expires_at = invitation.ExpiresAt,
            created_at = invitation.CreatedAt
        });
    }

}
