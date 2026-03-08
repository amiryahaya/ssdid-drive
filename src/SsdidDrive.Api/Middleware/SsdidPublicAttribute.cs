namespace SsdidDrive.Api.Middleware;

/// <summary>
/// Marks an endpoint as public (no SSDID session required).
/// The SsdidAuthMiddleware skips authentication for endpoints with this metadata.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class SsdidPublicAttribute : Attribute;
