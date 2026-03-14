namespace SsdidDrive.Api.Common;

/// <summary>
/// Scoped context populated by HmacAuthMiddleware for extension service requests.
/// </summary>
public class ExtensionServiceContext
{
    public Guid ServiceId { get; set; }
    public Guid TenantId { get; set; }
    public string ServiceName { get; set; } = default!;
    public Dictionary<string, bool> Permissions { get; set; } = new();

    public bool HasPermission(string permission)
        => Permissions.TryGetValue(permission, out var allowed) && allowed;
}
