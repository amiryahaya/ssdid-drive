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

        // SECURITY: Always return the same response to prevent user enumeration.
        // Whether the email is unknown, exists but has no TOTP, or is valid — same shape.
        if (user is null || !user.TotpEnabled)
        {
            // Simulate processing time to prevent timing oracle
            await Task.Delay(100, ct);
        }

        return Results.Ok(new { requires_totp = true, email });
    }
}
