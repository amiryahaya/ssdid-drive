using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Middleware;

public static class HmacSignatureHelper
{
    public static string ComputeBodyHash(string body)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(body));
        return Convert.ToHexStringLower(hash);
    }

    public static string ComputeSignature(byte[] secret, string timestamp, string method, string path, string bodyHash)
    {
        var stringToSign = $"{timestamp}\n{method}\n{path}\n{bodyHash}";
        var signatureBytes = HMACSHA256.HashData(secret, Encoding.UTF8.GetBytes(stringToSign));
        return Convert.ToBase64String(signatureBytes);
    }

    public static bool VerifySignature(byte[] secret, string timestamp, string method, string path, string bodyHash, string providedSignature)
    {
        try
        {
            var expected = ComputeSignature(secret, timestamp, method, path, bodyHash);
            var expectedBytes = Convert.FromBase64String(expected);
            var providedBytes = Convert.FromBase64String(providedSignature);
            return CryptographicOperations.FixedTimeEquals(expectedBytes, providedBytes);
        }
        catch (FormatException)
        {
            return false;
        }
    }
}

public class HmacReplayCache
{
    private readonly ConcurrentDictionary<string, DateTimeOffset> _seen = new();
    private DateTimeOffset _lastCleanup = DateTimeOffset.UtcNow;
    private static readonly TimeSpan CleanupInterval = TimeSpan.FromMinutes(2);

    public bool HasBeenSeen(Guid serviceId, string timestamp, string signature)
    {
        CleanupIfNeeded();
        var key = $"{serviceId}:{timestamp}:{signature}";
        return !_seen.TryAdd(key, DateTimeOffset.UtcNow);
    }

    private void CleanupIfNeeded()
    {
        var now = DateTimeOffset.UtcNow;
        if (now - _lastCleanup < CleanupInterval) return;
        _lastCleanup = now;

        var cutoff = now - TimeSpan.FromMinutes(6);
        foreach (var kvp in _seen)
        {
            if (kvp.Value < cutoff)
                _seen.TryRemove(kvp.Key, out _);
        }
    }
}

public class HmacAuthMiddleware(RequestDelegate next, ILogger<HmacAuthMiddleware> logger, HmacReplayCache replayCache)
{
    private static readonly TimeSpan MaxTimestampAge = TimeSpan.FromMinutes(5);

    private static readonly JsonSerializerOptions ProblemJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public async Task InvokeAsync(HttpContext context, AppDbContext db, ExtensionServiceContext serviceContext, TotpEncryption encryption)
    {
        var serviceIdHeader = context.Request.Headers["X-Service-Id"].FirstOrDefault();
        var timestampHeader = context.Request.Headers["X-Timestamp"].FirstOrDefault();
        var signatureHeader = context.Request.Headers["X-Signature"].FirstOrDefault();

        if (string.IsNullOrEmpty(serviceIdHeader) || string.IsNullOrEmpty(timestampHeader) || string.IsNullOrEmpty(signatureHeader))
        {
            await WriteProblem(context, 401, "Missing HMAC authentication headers");
            return;
        }

        if (!Guid.TryParse(serviceIdHeader, out var serviceId))
        {
            await WriteProblem(context, 401, "Invalid X-Service-Id format");
            return;
        }

        if (!DateTimeOffset.TryParse(timestampHeader, out var timestamp))
        {
            await WriteProblem(context, 401, "Invalid X-Timestamp format");
            return;
        }

        var age = DateTimeOffset.UtcNow - timestamp;
        if (age > MaxTimestampAge || age < -TimeSpan.FromMinutes(1))
        {
            await WriteProblem(context, 401, "Timestamp outside acceptable range");
            return;
        }

        var service = await db.ExtensionServices.FirstOrDefaultAsync(s => s.Id == serviceId);
        if (service is null || !service.Enabled)
        {
            await WriteProblem(context, 401, "Service not found or disabled");
            return;
        }

        byte[] secret;
        try
        {
            var decryptedKey = encryption.Decrypt(service.ServiceKey);
            secret = Convert.FromBase64String(decryptedKey);
        }
        catch
        {
            logger.LogError("Failed to decrypt service key for service {ServiceId}", serviceId);
            await WriteProblem(context, 500, "Internal server error");
            return;
        }

        context.Request.EnableBuffering();
        using var reader = new StreamReader(context.Request.Body, leaveOpen: true);
        var body = await reader.ReadToEndAsync();
        context.Request.Body.Position = 0;

        var bodyHash = HmacSignatureHelper.ComputeBodyHash(body);
        var method = context.Request.Method;
        var path = context.Request.Path.Value ?? "/";
        var query = context.Request.QueryString.Value ?? "";
        var pathAndQuery = query.Length > 0 ? $"{path}{query}" : path;

        if (!HmacSignatureHelper.VerifySignature(secret, timestampHeader, method, pathAndQuery, bodyHash, signatureHeader))
        {
            await WriteProblem(context, 401, "Invalid HMAC signature");
            return;
        }

        if (replayCache.HasBeenSeen(serviceId, timestampHeader, signatureHeader))
        {
            await WriteProblem(context, 401, "Duplicate request (replay detected)");
            return;
        }

        var permissions = new Dictionary<string, bool>();
        try
        {
            permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions)
                ?? new Dictionary<string, bool>();
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Malformed permissions JSON for service {ServiceId}", serviceId);
        }

        serviceContext.ServiceId = service.Id;
        serviceContext.TenantId = service.TenantId;
        serviceContext.ServiceName = service.Name;
        serviceContext.Permissions = permissions;

        try
        {
            service.LastUsedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(CancellationToken.None);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to update LastUsedAt for service {ServiceId}", serviceId);
        }

        await next(context);
    }

    private static Task WriteProblem(HttpContext context, int status, string detail)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = "application/problem+json";
        var title = status switch
        {
            401 => "Unauthorized",
            500 => "Internal Server Error",
            _ => "Error"
        };
        return context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Type = $"https://httpstatuses.com/{status}",
            Title = title,
            Status = status,
            Detail = detail
        }, ProblemJsonOptions);
    }
}
