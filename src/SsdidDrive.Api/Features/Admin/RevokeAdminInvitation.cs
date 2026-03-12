using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class RevokeAdminInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/tenants/{tenantId:guid}/invitations/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, Guid id, AppDbContext db,
        CurrentUserAccessor accessor, AuditService audit, CancellationToken ct)
    {
        var tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == tenantId, ct);
        if (tenant is null)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id && i.TenantId == tenantId, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.BadRequest("Only pending invitations can be revoked").ToProblemResult();

        invitation.Status = InvitationStatus.Revoked;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.User!.Id, "invitation.revoked",
            "Invitation", invitation.Id,
            $"Revoked invitation for {invitation.Email} to tenant {tenant.Name}", ct);

        return Results.NoContent();
    }
}
