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

        // Always return the same response to prevent user enumeration.
        // The actual existence/TOTP check happens in TotpVerify.
        var user = await db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null || !user.TotpEnabled)
        {
            // Simulate the same timing as a real lookup
            return Results.Ok(new { requires_totp = true, email });
        }

        return Results.Ok(new { requires_totp = true, email });
    }
}
