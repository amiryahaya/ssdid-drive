using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
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

public class HmacAuthMiddleware(RequestDelegate next, ILogger<HmacAuthMiddleware> logger)
{
    private static readonly TimeSpan MaxTimestampAge = TimeSpan.FromMinutes(5);

    public async Task InvokeAsync(HttpContext context, AppDbContext db, ExtensionServiceContext serviceContext, TotpEncryption encryption)
    {
        var serviceIdHeader = context.Request.Headers["X-Service-Id"].FirstOrDefault();
        var timestampHeader = context.Request.Headers["X-Timestamp"].FirstOrDefault();
        var signatureHeader = context.Request.Headers["X-Signature"].FirstOrDefault();

        if (string.IsNullOrEmpty(serviceIdHeader) || string.IsNullOrEmpty(timestampHeader) || string.IsNullOrEmpty(signatureHeader))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Missing HMAC authentication headers" });
            return;
        }

        if (!Guid.TryParse(serviceIdHeader, out var serviceId))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid X-Service-Id format" });
            return;
        }

        if (!DateTimeOffset.TryParse(timestampHeader, out var timestamp))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid X-Timestamp format" });
            return;
        }

        var age = DateTimeOffset.UtcNow - timestamp;
        if (age > MaxTimestampAge || age < -TimeSpan.FromMinutes(1))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Timestamp outside acceptable range" });
            return;
        }

        var service = await db.ExtensionServices.FirstOrDefaultAsync(s => s.Id == serviceId);
        if (service is null || !service.Enabled)
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Service not found or disabled" });
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
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(new { error = "Internal server error" });
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
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid HMAC signature" });
            return;
        }

        var permissions = new Dictionary<string, bool>();
        try
        {
            permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions)
                ?? new Dictionary<string, bool>();
        }
        catch { /* default to empty permissions */ }

        serviceContext.ServiceId = service.Id;
        serviceContext.TenantId = service.TenantId;
        serviceContext.ServiceName = service.Name;
        serviceContext.Permissions = permissions;

        service.LastUsedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(CancellationToken.None);

        await next(context);
    }
}
