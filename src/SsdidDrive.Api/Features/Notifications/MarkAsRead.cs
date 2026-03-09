using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Notifications;

public static class MarkAsRead
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/read", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var notification = await db.Notifications
            .FirstOrDefaultAsync(n => n.Id == id && n.UserId == user.Id, ct);

        if (notification is null)
            return AppError.NotFound("Notification not found").ToProblemResult();

        notification.IsRead = true;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new { notification.Id, notification.IsRead });
    }
}
