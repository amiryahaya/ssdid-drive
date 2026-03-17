using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class SendNotification
{
    public record Request(string Scope, Guid? TargetId, string Title, string Message);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/notifications", Handle);

    private static async Task<IResult> Handle(
        Request req, AppDbContext db, CurrentUserAccessor accessor,
        NotificationService notificationService, PushService pushService,
        AuditService audit, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Scope))
            return AppError.BadRequest("Scope is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.Title) || string.IsNullOrWhiteSpace(req.Message))
            return AppError.BadRequest("Title and message are required").ToProblemResult();

        var adminId = accessor.UserId;
        List<Guid> recipientIds;

        switch (req.Scope.ToLowerInvariant())
        {
            case "user":
                if (req.TargetId is null)
                    return AppError.BadRequest("target_id is required for user scope").ToProblemResult();
                var userExists = await db.Users.AnyAsync(u => u.Id == req.TargetId, ct);
                if (!userExists)
                    return AppError.NotFound("User not found").ToProblemResult();
                recipientIds = [req.TargetId.Value];
                break;

            case "tenant":
                if (req.TargetId is null)
                    return AppError.BadRequest("target_id is required for tenant scope").ToProblemResult();
                recipientIds = await db.UserTenants
                    .Where(ut => ut.TenantId == req.TargetId)
                    .Select(ut => ut.UserId)
                    .ToListAsync(ct);
                if (recipientIds.Count == 0)
                    return AppError.NotFound("Tenant has no members").ToProblemResult();
                break;

            case "broadcast":
                recipientIds = await db.Users
                    .Where(u => u.Status == UserStatus.Active)
                    .Select(u => u.Id)
                    .ToListAsync(ct);
                break;

            default:
                return AppError.BadRequest("Scope must be 'user', 'tenant', or 'broadcast'").ToProblemResult();
        }

        // Create in-app notifications for all recipients.
        // Skip per-user push — we send one efficient push call below.
        var isBroadcast = req.Scope.Equals("broadcast", StringComparison.OrdinalIgnoreCase);
        foreach (var userId in recipientIds)
        {
            await notificationService.CreateAsync(
                userId, "admin_announcement", req.Title, req.Message, skipPush: true, ct: ct);
        }

        // Send push once (not N times): broadcast uses segment, others use external IDs
        if (isBroadcast)
            _ = pushService.BroadcastAsync(req.Title, req.Message, ct: CancellationToken.None);
        else
            _ = pushService.SendToUsersAsync(
                recipientIds.ConvertAll(id => id.ToString()),
                req.Title, req.Message, ct: CancellationToken.None);

        // Log the sent message
        db.NotificationLogs.Add(new NotificationLog
        {
            Id = Guid.NewGuid(),
            SentById = adminId,
            Scope = req.Scope.ToLowerInvariant(),
            TargetId = req.TargetId,
            Title = req.Title,
            Message = req.Message,
            RecipientCount = recipientIds.Count,
            CreatedAt = DateTimeOffset.UtcNow
        });

        await db.SaveChangesAsync(ct);

        // Audit log
        await audit.LogAsync(adminId, "admin_notification_sent", null, null,
            $"Scope: {req.Scope}, recipients: {recipientIds.Count}, title: {req.Title}", ct);

        return Results.Ok(new { recipients = recipientIds.Count });
    }
}
