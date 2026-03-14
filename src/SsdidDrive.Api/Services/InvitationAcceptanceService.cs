using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class InvitationAcceptanceService(AppDbContext db, NotificationService notifications)
{
    public record AcceptResult(Guid InvitationId, Guid TenantId, string TenantName, string TenantSlug, TenantRole Role);

    public async Task<Result<AcceptResult>> AcceptAsync(
        Guid userId,
        string? callerEmail,
        Guid? invitationId = null,
        string? token = null,
        string? tokenProof = null,
        string? acceptedByDid = null,
        CancellationToken ct = default)
    {
        // 1. Look up invitation
        Invitation? invitation;
        if (invitationId.HasValue)
        {
            invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => i.Id == invitationId.Value, ct);
        }
        else if (!string.IsNullOrWhiteSpace(token))
        {
            invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => i.Token == token || i.ShortCode == token, ct);
        }
        else
        {
            return AppError.BadRequest("Invitation ID or token is required");
        }

        if (invitation is null)
            return AppError.NotFound("Invitation not found");

        // 2. Check expiry
        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            if (invitation.Status == InvitationStatus.Pending)
            {
                invitation.Status = InvitationStatus.Expired;
                invitation.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(ct);
            }
            return AppError.Gone("Invitation has expired");
        }

        // 3. Check status
        if (invitation.Status == InvitationStatus.Accepted)
            return AppError.Conflict("Invitation has already been accepted");

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.NotFound("Invitation not found or is no longer valid");

        // 4. Check user is not suspended
        var user = await db.Users.FindAsync([userId], ct);
        if (user is null)
            return AppError.NotFound("User not found");

        if (user.Status == UserStatus.Suspended)
            return AppError.Forbidden("Your account is suspended");

        // 5. Email matching (if invitation specifies an email)
        if (!string.IsNullOrWhiteSpace(invitation.Email) && !string.IsNullOrWhiteSpace(callerEmail))
        {
            if (!string.Equals(invitation.Email.Trim(), callerEmail.Trim(), StringComparison.OrdinalIgnoreCase))
                return AppError.Forbidden("Email does not match the invitation");
        }

        // 6. Authorization: if InvitedUserId is set, only that user can accept
        if (invitation.InvitedUserId is not null && invitation.InvitedUserId != userId)
            return AppError.Forbidden("You are not the invited user");

        // 6b. For open invitations (InvitedUserId is null) via authenticated accept,
        // require constant-time token proof to prevent GUID brute-force
        if (invitation.InvitedUserId is null && invitationId.HasValue)
        {
            if (string.IsNullOrWhiteSpace(tokenProof) ||
                !System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                    System.Text.Encoding.UTF8.GetBytes(tokenProof),
                    System.Text.Encoding.UTF8.GetBytes(invitation.Token)))
                return AppError.Forbidden("Invalid or missing invitation token");
        }

        // 7. Check duplicate membership
        var existingMembership = await db.UserTenants
            .AnyAsync(ut => ut.UserId == userId && ut.TenantId == invitation.TenantId, ct);

        if (existingMembership)
            return AppError.Conflict("You are already a member of this tenant");

        // 8. Begin transaction for atomic acceptance
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // 9. Atomic claim (WHERE Status = Pending prevents double-accept)
        var updated = await db.Invitations
            .Where(i => i.Id == invitation.Id && i.Status == InvitationStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Status, InvitationStatus.Accepted)
                .SetProperty(i => i.InvitedUserId, userId)
                .SetProperty(i => i.AcceptedByAccountId, userId)
                .SetProperty(i => i.AcceptedByDid, acceptedByDid)
                .SetProperty(i => i.AcceptedAt, DateTimeOffset.UtcNow)
                .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

        if (updated == 0)
            return AppError.Conflict("Invitation has already been processed");

        // 10. Create UserTenant
        db.UserTenants.Add(new UserTenant
        {
            UserId = userId,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
            CreatedAt = DateTimeOffset.UtcNow
        });

        // 11. Notify inviter
        await notifications.CreateAsync(
            invitation.InvitedById,
            "invitation_accepted",
            "Invitation Accepted",
            $"{user.DisplayName ?? user.Did ?? user.Email ?? "A user"} accepted your invitation",
            actionType: "invitation",
            actionResourceId: invitation.Id.ToString(),
            ct: ct);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            return AppError.Conflict("User is already a member of this tenant");
        }

        await transaction.CommitAsync(ct);

        return new AcceptResult(
            invitation.Id,
            invitation.TenantId,
            invitation.Tenant.Name,
            invitation.Tenant.Slug,
            invitation.Role);
    }
}
