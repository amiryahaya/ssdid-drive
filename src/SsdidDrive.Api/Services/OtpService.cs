using System.Security.Cryptography;
using Microsoft.Extensions.Caching.Distributed;

namespace SsdidDrive.Api.Services;

public record OtpEntry(string Code, DateTimeOffset ExpiresAt, int Attempts);

public interface IOtpStore
{
    Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default);
    Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default);
    Task DeleteAsync(string key, CancellationToken ct = default);
}

public class OtpService(IOtpStore store)
{
    private const int MaxAttempts = 5;
    private static readonly TimeSpan Ttl = TimeSpan.FromMinutes(10);

    public async Task<string> GenerateAsync(string email, string purpose, CancellationToken ct = default)
    {
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var key = BuildKey(email, purpose);
        var entry = new OtpEntry(code, DateTimeOffset.UtcNow.Add(Ttl), 0);
        await store.StoreAsync(key, entry, Ttl, ct);
        return code;
    }

    public async Task<bool> VerifyAsync(string email, string purpose, string code, CancellationToken ct = default)
    {
        var key = BuildKey(email, purpose);
        var entry = await store.GetAsync(key, ct);

        if (entry is null || entry.ExpiresAt < DateTimeOffset.UtcNow)
            return false;

        if (entry.Attempts >= MaxAttempts)
        {
            await store.DeleteAsync(key, ct);
            return false;
        }

        if (entry.Code != code)
        {
            var updated = entry with { Attempts = entry.Attempts + 1 };
            await store.StoreAsync(key, updated, entry.ExpiresAt - DateTimeOffset.UtcNow, ct);
            return false;
        }

        await store.DeleteAsync(key, ct);
        return true;
    }

    private static string BuildKey(string email, string purpose) =>
        $"ssdid:otp:{email.ToLowerInvariant()}:{purpose}";
}

public class InMemoryOtpStore : IOtpStore
{
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, OtpEntry> _store = new();

    public Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default)
    {
        _store[key] = entry;
        return Task.CompletedTask;
    }

    public Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default)
    {
        _store.TryGetValue(key, out var entry);
        if (entry is not null && entry.ExpiresAt < DateTimeOffset.UtcNow)
        {
            _store.TryRemove(key, out _);
            return Task.FromResult<OtpEntry?>(null);
        }
        return Task.FromResult(entry);
    }

    public Task DeleteAsync(string key, CancellationToken ct = default)
    {
        _store.TryRemove(key, out _);
        return Task.CompletedTask;
    }
}

public class RedisOtpStore(IDistributedCache cache) : IOtpStore
{
    public async Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(entry);
        await cache.SetStringAsync(key, json, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = ttl
        }, ct);
    }

    public async Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default)
    {
        var json = await cache.GetStringAsync(key, ct);
        return json is null ? null : System.Text.Json.JsonSerializer.Deserialize<OtpEntry>(json);
    }

    public async Task DeleteAsync(string key, CancellationToken ct = default)
    {
        await cache.RemoveAsync(key, ct);
    }
}
