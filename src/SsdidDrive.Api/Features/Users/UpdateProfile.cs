using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Users;

public static class UpdateProfile
{
    public record Request(string? DisplayName, string? Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/me", Handle);

    private static async Task<IResult> Handle(CurrentUserAccessor accessor, AppDbContext db, Request req)
    {
        if (req.DisplayName is not null && req.DisplayName.Length > 256)
            return AppError.BadRequest("DisplayName must be 256 chars or less").ToProblemResult();
        if (req.Email is not null && req.Email.Length > 160)
            return AppError.BadRequest("Email must be 160 chars or less").ToProblemResult();

        // Re-fetch with tracking for mutation (middleware loads AsNoTracking)
        var user = await db.Users.FindAsync(accessor.UserId);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        // Only allow updating fields that are currently empty
        if (req.DisplayName is not null)
        {
            if (!string.IsNullOrWhiteSpace(user.DisplayName))
                return AppError.BadRequest("Display name is already set and cannot be changed").ToProblemResult();
            user.DisplayName = req.DisplayName;
        }

        if (req.Email is not null)
        {
            if (!string.IsNullOrWhiteSpace(user.Email))
                return AppError.BadRequest("Email is already set and cannot be changed").ToProblemResult();
            user.Email = req.Email;
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();
        return Results.Ok(new { user.Id, user.Did, user.DisplayName, user.Email });
    }
}
