using System.Net.Http.Json;
using Microsoft.Extensions.Options;

namespace SsdidDrive.Api.Services;

public class OneSignalOptions
{
    public string AppId { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
}

public class PushService
{
    private readonly HttpClient _httpClient;
    private readonly OneSignalOptions _options;
    private readonly ILogger<PushService> _logger;
    private readonly bool _enabled;

    public PushService(HttpClient httpClient, IOptions<OneSignalOptions> options, ILogger<PushService> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
        _enabled = !string.IsNullOrEmpty(_options.AppId) && !string.IsNullOrEmpty(_options.ApiKey);

        if (_enabled)
        {
            _httpClient.BaseAddress = new Uri("https://api.onesignal.com/");
            _httpClient.DefaultRequestHeaders.Add("Authorization", $"Key {_options.ApiKey}");
        }
    }

    public async Task SendToUsersAsync(
        IReadOnlyList<string> externalUserIds, string title, string message,
        string? actionType = null, string? resourceId = null, CancellationToken ct = default)
    {
        if (!_enabled || externalUserIds.Count == 0) return;

        var payload = new
        {
            app_id = _options.AppId,
            include_aliases = new { external_id = externalUserIds },
            target_channel = "push",
            headings = new { en = title },
            contents = new { en = message },
            data = new Dictionary<string, string?>
            {
                ["action_type"] = actionType,
                ["resource_id"] = resourceId
            }
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync("notifications", payload, ct);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("OneSignal push failed ({Status}): {Body}", response.StatusCode, body);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send push notification via OneSignal");
        }
    }

    public async Task BroadcastAsync(
        string title, string message,
        string? actionType = null, string? resourceId = null, CancellationToken ct = default)
    {
        if (!_enabled) return;

        var payload = new
        {
            app_id = _options.AppId,
            included_segments = new[] { "Subscribed Users" },
            headings = new { en = title },
            contents = new { en = message },
            data = new Dictionary<string, string?>
            {
                ["action_type"] = actionType,
                ["resource_id"] = resourceId
            }
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync("notifications", payload, ct);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("OneSignal broadcast failed ({Status}): {Body}", response.StatusCode, body);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to broadcast push notification via OneSignal");
        }
    }
}
