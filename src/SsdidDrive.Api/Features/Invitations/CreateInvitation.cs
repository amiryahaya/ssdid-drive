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

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, NotificationService notifications, CancellationToken ct)
    {
        var user = accessor.User!;

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

        var now = DateTimeOffset.UtcNow;
        var token = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');

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

        return Results.Created($"/api/invitations/{invitation.Id}", new
        {
            invitation.Id,
            invitation.TenantId,
            invitation.InvitedById,
            invitation.Email,
            invitation.InvitedUserId,
            Role = invitation.Role.ToString().ToLowerInvariant(),
            Status = invitation.Status.ToString().ToLowerInvariant(),
            invitation.Token,
            invitation.Message,
            invitation.ExpiresAt,
            invitation.CreatedAt
        });
    }
}
