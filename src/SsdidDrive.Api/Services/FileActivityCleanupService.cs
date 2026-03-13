using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Services;

public class FileActivityCleanupService(
    IServiceProvider services,
    ILogger<FileActivityCleanupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var now = DateTimeOffset.UtcNow;
        var nextRun = new DateTimeOffset(now.Date.AddDays(now.Hour >= 3 ? 1 : 0).AddHours(3), TimeSpan.Zero);
        var delay = nextRun - now;

        logger.LogInformation("FileActivity cleanup scheduled. Next run at {NextRun:u}", nextRun);

        try
        {
            await Task.Delay(delay, stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                await RunCleanupAsync(stoppingToken);
                await Task.Delay(TimeSpan.FromDays(1), stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Graceful shutdown
        }
    }

    private async Task RunCleanupAsync(CancellationToken ct)
    {
        try
        {
            using var scope = services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var cutoff = DateTimeOffset.UtcNow.AddDays(-90);
            var totalDeleted = 0;

            int deleted;
            do
            {
                deleted = await db.FileActivities
                    .Where(a => a.CreatedAt < cutoff)
                    .Take(1000)
                    .ExecuteDeleteAsync(ct);
                totalDeleted += deleted;
            } while (deleted == 1000);

            if (totalDeleted > 0)
                logger.LogInformation("FileActivity cleanup: deleted {Count} entries older than 90 days", totalDeleted);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "FileActivity cleanup failed");
        }
    }
}
