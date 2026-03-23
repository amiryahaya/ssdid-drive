using System.Text.Json;
using System.Text.Json.Serialization;

namespace SsdidDrive.Api.Common;

/// <summary>
/// Dedicated JSON context for Verifiable Credential serialization.
/// Uses camelCase to comply with W3C VC spec, separate from the
/// global snake_case policy used for the REST API.
/// </summary>
public static class VcSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static IResult ToJsonResult<T>(T value, int statusCode = 200)
        => Results.Text(Serialize(value), "application/json", statusCode: statusCode);
}
