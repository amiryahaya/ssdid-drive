using System.Text.Json;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class FileActivityService(AppDbContext db, ILogger<FileActivityService> logger)
{
    public async Task LogAsync(
        Guid actorId,
        Guid tenantId,
        string eventType,
        string resourceType,
        Guid resourceId,
        string resourceName,
        Guid resourceOwnerId,
        object? details = null,
        CancellationToken ct = default)
    {
        try
        {
            var activity = new FileActivity
            {
                Id = Guid.NewGuid(),
                ActorId = actorId,
                TenantId = tenantId,
                EventType = eventType,
                ResourceType = resourceType,
                ResourceId = resourceId,
                ResourceName = resourceName,
                ResourceOwnerId = resourceOwnerId,
                Details = details is not null
                    ? JsonDocument.Parse(JsonSerializer.Serialize(details))
                    : null,
                CreatedAt = DateTimeOffset.UtcNow
            };

            db.FileActivities.Add(activity);
            await db.SaveChangesAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to log file activity: {EventType} for resource {ResourceId}", eventType, resourceId);
        }
    }
}
