using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace SsdidDrive.Api.Health;

public class RedisHealthCheck(IConnectionMultiplexer redis) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        try
        {
            var db = redis.GetDatabase();
            var latency = await db.PingAsync();
            return HealthCheckResult.Healthy($"Redis ping: {latency.TotalMilliseconds:F1}ms");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Redis unreachable", ex);
        }
    }
}
