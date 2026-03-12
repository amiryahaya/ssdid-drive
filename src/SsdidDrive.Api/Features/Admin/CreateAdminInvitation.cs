using System.Net.Mail;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Features.Invitations;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class CreateAdminInvitation
{
    private record Request(string? Email, string? Role, string? Message);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenants/{tenantId:guid}/invitations", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, Request req, AppDbContext db,
        CurrentUserAccessor accessor, NotificationService notifications,
        EmailService? emailService, AuditService audit, ILoggerFactory loggerFactory,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        if (!MailAddress.TryCreate(req.Email, out _))
            return AppError.BadRequest("Invalid email address format").ToProblemResult();

        var normalizedEmail = req.Email.Trim().ToLowerInvariant();

        if (req.Message is { Length: > 500 })
            return AppError.BadRequest("Message must be 500 characters or fewer").ToProblemResult();

        var role = req.Role?.ToLowerInvariant() switch
        {
            "owner" => TenantRole.Owner,
            "admin" => TenantRole.Admin,
            _ => (TenantRole?)null
        };

        if (role is null)
            return AppError.BadRequest("Role must be 'owner' or 'admin'").ToProblemResult();

        var tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == tenantId, ct);
        if (tenant is null)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        var existingMember = await db.Users
            .Where(u => u.Email == normalizedEmail)
            .Join(db.UserTenants.Where(ut => ut.TenantId == tenantId),
                u => u.Id, ut => ut.UserId, (u, ut) => u)
            .AnyAsync(ct);

        if (existingMember)
            return AppError.Conflict("This user is already a member of the tenant").ToProblemResult();

        var duplicatePending = await db.Invitations
            .AnyAsync(i => i.TenantId == tenantId
                && i.Email == normalizedEmail
                && i.Status == InvitationStatus.Pending, ct);

        if (duplicatePending)
            return AppError.Conflict("A pending invitation already exists for this email").ToProblemResult();

        var now = DateTimeOffset.UtcNow;
        var token = InvitationHelper.GenerateToken();

        string shortCode;
        try
        {
            shortCode = await InvitationHelper.GenerateShortCode(db, tenant.Slug, ct);
        }
        catch (InvalidOperationException)
        {
            return AppError.BadRequest("Unable to generate invitation code, please try again").ToProblemResult();
        }

        Guid? invitedUserId = null;
        var invitedUser = await db.Users.FirstOrDefaultAsync(u => u.Email == normalizedEmail, ct);
        invitedUserId = invitedUser?.Id;

        var user = accessor.User!;

        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            InvitedById = user.Id,
            InvitedUserId = invitedUserId,
            Email = normalizedEmail,
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
                $"You've been invited to join {tenant.Name} as {role.Value.ToString().ToLowerInvariant()}",
                actionType: "invitation",
                actionResourceId: invitation.Id.ToString(),
                ct: ct);
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.InnerException?.Message.Contains("ix_invitations_pending_email_tenant") == true)
        {
            return AppError.Conflict("A pending invitation already exists for this email").ToProblemResult();
        }

        await audit.LogAsync(user.Id, "invitation.created",
            "Invitation", invitation.Id,
            $"Invited {normalizedEmail} as {role.Value.ToString().ToLowerInvariant()} to tenant {tenant.Name}", ct);

        if (emailService is not null)
        {
            var email = normalizedEmail;
            var tenantName = tenant.Name;
            var roleName = role.Value.ToString().ToLowerInvariant();
            var msg = req.Message;
            var logger = loggerFactory.CreateLogger(typeof(CreateAdminInvitation).FullName!);
            _ = Task.Run(async () =>
            {
                try { await emailService.SendInvitationAsync(email, tenantName, roleName, shortCode, msg); }
                catch (Exception ex) { logger.LogError(ex, "Failed to send invitation email to {Email}", email); }
            });
        }

        return Results.Created($"/api/admin/tenants/{tenantId}/invitations/{invitation.Id}", new
        {
            id = invitation.Id,
            tenant_id = invitation.TenantId,
            invited_by_id = invitation.InvitedById,
            email = invitation.Email,
            invited_user_id = invitation.InvitedUserId,
            role = invitation.Role.ToString().ToLowerInvariant(),
            status = invitation.Status.ToString().ToLowerInvariant(),
            short_code = invitation.ShortCode,
            message = invitation.Message,
            expires_at = invitation.ExpiresAt,
            created_at = invitation.CreatedAt
        });
    }
}
