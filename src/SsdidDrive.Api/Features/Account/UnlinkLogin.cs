using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class UnlinkLogin
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/logins/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        CurrentUserAccessor accessor,
        AppDbContext db,
        AuditService auditService,
        CancellationToken ct)
    {
        var login = await db.Logins
            .FirstOrDefaultAsync(l => l.Id == id && l.AccountId == accessor.UserId, ct);

        if (login is null)
            return AppError.NotFound("Login not found").ToProblemResult();

        var loginCount = await db.Logins
            .CountAsync(l => l.AccountId == accessor.UserId, ct);

        if (loginCount <= 1)
            return AppError.BadRequest("Cannot remove your only login method").ToProblemResult();

        var provider = login.Provider.ToString().ToLowerInvariant();
        db.Logins.Remove(login);
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.unlinked", "login", id,
            $"Provider: {provider}", ct);

        return Results.Ok(new { unlinked = true });
    }
}
