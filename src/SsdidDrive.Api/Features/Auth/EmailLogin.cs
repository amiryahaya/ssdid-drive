using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailLogin
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/login", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("No account with this email").ToProblemResult();

        if (!user.TotpEnabled)
            return AppError.BadRequest("TOTP is not set up for this account").ToProblemResult();

        return Results.Ok(new { requires_totp = true, email });
    }
}
