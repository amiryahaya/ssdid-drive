using Microsoft.AspNetCore.Mvc;
using Ssdid.Sdk.Server;

namespace SsdidDrive.Api.Common;

public record AppError(string Type, string Title, int Status, string? Detail = null)
{
    public static AppError BadRequest(string detail) => new("bad_request", "Bad Request", 400, detail);
    public static AppError NotFound(string detail) => new("not_found", "Not Found", 404, detail);
    public static AppError Unauthorized(string detail) => new("unauthorized", "Unauthorized", 401, detail);
    public static AppError Forbidden(string detail) => new("forbidden", "Forbidden", 403, detail);
    public static AppError Gone(string detail) => new("gone", "Gone", 410, detail);
    public static AppError Conflict(string detail) => new("conflict", "Conflict", 409, detail);
    public static AppError ServiceUnavailable(string detail) => new("service_unavailable", "Service Unavailable", 503, detail);

    public static AppError FromSsdidError(SsdidError err)
    {
        var status = err.HttpStatus ?? 500;
        var title = status switch
        {
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            409 => "Conflict",
            503 => "Service Unavailable",
            _ => "Error"
        };
        return new AppError(err.Code, title, status, err.Message);
    }

    public IResult ToProblemResult() => Results.Problem(new ProblemDetails
    {
        Type = $"https://httpstatuses.com/{Status}",
        Title = Title,
        Status = Status,
        Detail = Detail,
        Extensions = { ["errorType"] = Type }
    });
}

/// <summary>
/// Extension methods to bridge SsdidError to IResult via AppError.
/// </summary>
public static class SsdidErrorExtensions
{
    public static IResult ToProblemResult(this SsdidError err) =>
        AppError.FromSsdidError(err).ToProblemResult();
}
