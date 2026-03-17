using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Users;

public static class SwitchTenant
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/me/switch-tenant/{tenantId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId,
        AppDbContext db,
        CurrentUserAccessor accessor,
        ISessionStore sessionStore,
        AuditService audit,
        CancellationToken ct)
    {
        var oldToken = accessor.SessionToken!;
        var oldTenantId = accessor.User!.TenantId;

        var membership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == accessor.UserId && ut.TenantId == tenantId, ct);

        if (membership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        // Issue new session token BEFORE committing DB change.
        // If session creation fails, the user stays in their current tenant (safe).
        var newToken = sessionStore.CreateSession(accessor.UserId.ToString());
        if (newToken is null)
            return AppError.ServiceUnavailable("Session limit reached, try again later").ToProblemResult();

        // Re-fetch with tracking for mutation (middleware loads AsNoTracking)
        var user = await db.Users.FindAsync([accessor.UserId], ct);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        // Update active tenant
        user.TenantId = tenantId;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // Audit log BEFORE revoking old token — if audit fails, old token
        // stays valid so the user is not locked out.
        await audit.LogAsync(
            user.Id,
            "tenant_switch",
            targetType: "tenant",
            targetId: tenantId,
            details: $"Switched from tenant {oldTenantId} to {tenantId}",
            ct: ct);

        // Revoke old session token last (after everything else succeeded)
        sessionStore.DeleteSession(oldToken);

        return Results.Ok(new
        {
            active_tenant_id = tenantId,
            role = membership.Role.ToString().ToLowerInvariant(),
            session_token = newToken
        });
    }
}
