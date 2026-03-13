using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class FileActivityService(IServiceScopeFactory scopeFactory, ILogger<FileActivityService> logger)
{
    private const int MaxDetailsLength = 4096;

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
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            var serialized = details is not null ? JsonSerializer.Serialize(details) : null;
            if (serialized?.Length > MaxDetailsLength)
                serialized = serialized[..MaxDetailsLength];

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
                Details = serialized,
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
