using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Services;

public class FileActivityCleanupService(
    IServiceProvider services,
    ILogger<FileActivityCleanupService> logger) : IHostedService, IDisposable
{
    private Timer? _timer;

    public Task StartAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var nextRun = new DateTimeOffset(now.Date.AddDays(now.Hour >= 3 ? 1 : 0).AddHours(3), TimeSpan.Zero);
        var delay = nextRun - now;

        _timer = new Timer(ExecuteCleanup, null, delay, TimeSpan.FromDays(1));
        logger.LogInformation("FileActivity cleanup scheduled. Next run at {NextRun:u}", nextRun);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken ct)
    {
        _timer?.Change(Timeout.Infinite, 0);
        return Task.CompletedTask;
    }

    private async void ExecuteCleanup(object? state)
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
                    .ExecuteDeleteAsync();
                totalDeleted += deleted;
            } while (deleted == 1000);

            if (totalDeleted > 0)
                logger.LogInformation("FileActivity cleanup: deleted {Count} entries older than 90 days", totalDeleted);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "FileActivity cleanup failed");
        }
    }

    public void Dispose() => _timer?.Dispose();
}
