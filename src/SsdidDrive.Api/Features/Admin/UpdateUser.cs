using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class UpdateUser
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/users/{id:guid}", Handle);

    private record UpdateUserRequest(string? Status, string? SystemRole);

    private static async Task<IResult> Handle(
        Guid id,
        UpdateUserRequest request,
        CurrentUserAccessor accessor,
        AppDbContext db,
        AuditService audit,
        CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        if (request.Status is not null)
        {
            if (request.Status is not ("active" or "suspended"))
                return AppError.BadRequest("Status must be 'active' or 'suspended'").ToProblemResult();

            if (request.Status == "suspended" && id == accessor.UserId)
                return AppError.BadRequest("Cannot suspend your own account").ToProblemResult();

            user.Status = request.Status == "active" ? UserStatus.Active : UserStatus.Suspended;
        }

        if (request.SystemRole is not null)
        {
            if (request.SystemRole == "SuperAdmin")
                user.SystemRole = Data.Entities.SystemRole.SuperAdmin;
            else if (request.SystemRole == "")
                user.SystemRole = null;
            else
                return AppError.BadRequest("System role must be 'SuperAdmin' or empty string to remove").ToProblemResult();
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, $"user.{request.Status ?? "updated"}", "user", id, ct: ct);

        return Results.Ok(new
        {
            id = user.Id,
            did = user.Did,
            display_name = user.DisplayName,
            email = user.Email,
            status = user.Status.ToString().ToLower(),
            system_role = user.SystemRole?.ToString(),
            tenant_id = user.TenantId,
            last_login_at = user.LastLoginAt,
            created_at = user.CreatedAt
        });
    }
}
