using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Services;

public class OidcCodeExchanger
{
    private readonly Dictionary<string, OidcProviderConfig> _providers;
    private readonly HttpClient _httpClient;
    private readonly ILogger<OidcCodeExchanger> _logger;

    public OidcCodeExchanger(IConfiguration config, HttpClient httpClient, ILogger<OidcCodeExchanger> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
        _providers = new Dictionary<string, OidcProviderConfig>(StringComparer.OrdinalIgnoreCase)
        {
            ["google"] = new(
                config["Oidc:Google:ClientId"] ?? "",
                config["Oidc:Google:ClientSecret"] ?? "",
                config["Oidc:Google:RedirectUri"] ?? "",
                "https://accounts.google.com/o/oauth2/v2/auth",
                "https://oauth2.googleapis.com/token"
            ),
            ["microsoft"] = new(
                config["Oidc:Microsoft:ClientId"] ?? "",
                config["Oidc:Microsoft:ClientSecret"] ?? "",
                config["Oidc:Microsoft:RedirectUri"] ?? "",
                "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                "https://login.microsoftonline.com/common/oauth2/v2.0/token"
            )
        };
    }

    /// <summary>
    /// Builds the authorization URL with PKCE. Returns null if provider is unsupported or unconfigured.
    /// </summary>
    public (string Url, string State, string CodeVerifier)? GetAuthorizationUrl(string provider, string state)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return null;

        if (string.IsNullOrEmpty(config.ClientId) || string.IsNullOrEmpty(config.ClientSecret)
            || string.IsNullOrEmpty(config.RedirectUri))
            return null;

        var codeVerifier = GenerateCodeVerifier();
        var codeChallenge = ComputeCodeChallenge(codeVerifier);

        var query = new Dictionary<string, string>
        {
            ["client_id"] = config.ClientId,
            ["redirect_uri"] = config.RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid email profile",
            ["state"] = state,
            ["code_challenge"] = codeChallenge,
            ["code_challenge_method"] = "S256",
        };

        var queryString = string.Join("&", query.Select(kvp =>
            $"{Uri.EscapeDataString(kvp.Key)}={Uri.EscapeDataString(kvp.Value)}"));

        return ($"{config.AuthorizeUrl}?{queryString}", state, codeVerifier);
    }

    /// <summary>
    /// Exchanges an authorization code for an ID token. Returns the raw ID token string.
    /// </summary>
    public async Task<Result<string>> ExchangeCodeAsync(
        string provider, string code, string codeVerifier, CancellationToken ct = default)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return AppError.BadRequest($"Unsupported OIDC provider: {provider}");

        if (string.IsNullOrEmpty(config.ClientId) || string.IsNullOrEmpty(config.ClientSecret))
            return AppError.ServiceUnavailable($"OIDC provider '{provider}' is not configured");

        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["code"] = code,
            ["redirect_uri"] = config.RedirectUri,
            ["client_id"] = config.ClientId,
            ["client_secret"] = config.ClientSecret,
            ["code_verifier"] = codeVerifier,
        };

        var response = await _httpClient.PostAsync(config.TokenUrl, new FormUrlEncodedContent(body), ct);
        var responseBody = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogWarning("OIDC token exchange failed for provider {Provider}: {Status} {Body}",
                provider, response.StatusCode, responseBody);
            return AppError.Unauthorized("Token exchange failed");
        }

        var json = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!json.TryGetProperty("id_token", out var idTokenProp))
            return AppError.Unauthorized("Token response missing id_token");

        return idTokenProp.GetString()!;
    }

    private static string GenerateCodeVerifier()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64UrlEncode(bytes);
    }

    private static string ComputeCodeChallenge(string codeVerifier)
    {
        var hash = SHA256.HashData(Encoding.ASCII.GetBytes(codeVerifier));
        return Base64UrlEncode(hash);
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private record OidcProviderConfig(
        string ClientId, string ClientSecret, string RedirectUri,
        string AuthorizeUrl, string TokenUrl);
}
