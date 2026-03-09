using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
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
        var did = sessionStore.GetSession(token);

        if (did is null)
        {
            await WriteProblem(context, 401, "Invalid or expired session");
            return;
        }

        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Did == did);
        if (user is null)
        {
            await WriteProblem(context, 401, "No account linked to this DID");
            return;
        }

        if (user.Status == Data.Entities.UserStatus.Suspended)
        {
            await WriteProblem(context, 403, "Account is suspended");
            return;
        }

        accessor.UserId = user.Id;
        accessor.Did = user.Did;
        accessor.User = user;
        accessor.SessionToken = token;
        accessor.SystemRole = user.SystemRole;

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
