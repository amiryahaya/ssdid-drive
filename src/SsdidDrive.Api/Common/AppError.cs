using Microsoft.AspNetCore.Mvc;

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

    public IResult ToProblemResult() => Results.Problem(new ProblemDetails
    {
        Type = $"https://httpstatuses.com/{Status}",
        Title = Title,
        Status = Status,
        Detail = Detail,
        Extensions = { ["errorType"] = Type }
    });
}
