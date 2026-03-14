using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Middleware;

public class SsdidAuthMiddleware(RequestDelegate next)
{
    private static readonly JsonSerializerOptions ProblemJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public async Task InvokeAsync(HttpContext context, ISessionStore sessionStore, AppDbContext db, CurrentUserAccessor accessor)
    {
        // Skip auth for endpoints marked with [SsdidPublic]
        var endpoint = context.GetEndpoint();
        if (endpoint?.Metadata.GetMetadata<SsdidPublicAttribute>() is not null)
        {
            await next(context);
            return;
        }

        var authHeader = context.Request.Headers.Authorization.FirstOrDefault();

        if (authHeader is null || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            await WriteProblem(context, 401, "Missing or invalid Authorization header");
            return;
        }

        var token = authHeader["Bearer ".Length..];
        var sessionValue = sessionStore.GetSession(token);

        if (sessionValue is null)
        {
            await WriteProblem(context, 401, "Invalid or expired session");
            return;
        }

        // Detect session type and resolve user
        User? user;
        bool mfaPending = false;

        var effectiveValue = sessionValue;
        if (sessionValue.StartsWith("mfa:", StringComparison.Ordinal))
        {
            mfaPending = true;
            effectiveValue = sessionValue[4..];
        }

        if (Guid.TryParse(effectiveValue, out var accountId))
        {
            // New auth: session value is Account.Id (UUID)
            user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == accountId);
        }
        else
        {
            // Legacy SSDID auth: session value is DID string
            user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Did == sessionValue);
        }

        if (user is null)
        {
            await WriteProblem(context, 401, "No account found for this session");
            return;
        }

        if (user.Status == UserStatus.Suspended)
        {
            await WriteProblem(context, 403, "Account is suspended");
            return;
        }

        // If MFA pending, only allow TOTP verify endpoint
        if (mfaPending)
        {
            var path = context.Request.Path.Value ?? "";
            if (!path.Equals("/api/auth/totp/verify", StringComparison.OrdinalIgnoreCase))
            {
                await WriteProblem(context, 403, "MFA verification required");
                return;
            }
        }

        accessor.UserId = user.Id;
        accessor.Did = user.Did;
        accessor.User = user;
        accessor.SessionToken = token;
        accessor.SystemRole = user.SystemRole;
        accessor.MfaPending = mfaPending;

        await next(context);
    }

    private static Task WriteProblem(HttpContext context, int status, string detail)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = "application/problem+json";
        return context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Type = $"https://httpstatuses.com/{status}",
            Title = "Unauthorized",
            Status = status,
            Detail = detail
        }, ProblemJsonOptions);
    }
}
