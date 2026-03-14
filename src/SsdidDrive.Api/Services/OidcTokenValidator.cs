using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Services;

public record OidcClaims(string Subject, string Email, string? Name);

public class OidcTokenValidator
{
    private readonly Dictionary<string, ProviderConfig> _providers;
    private readonly ConcurrentDictionary<string, ConfigurationManager<OpenIdConnectConfiguration>> _configManagers = new();
    private readonly ILogger<OidcTokenValidator> _logger;

    public OidcTokenValidator(IConfiguration config, ILogger<OidcTokenValidator> logger)
    {
        _logger = logger;
        _providers = new Dictionary<string, ProviderConfig>(StringComparer.OrdinalIgnoreCase)
        {
            ["google"] = new(
                config["Oidc:Google:ClientId"] ?? "",
                "https://accounts.google.com/.well-known/openid-configuration",
                "https://accounts.google.com"
            ),
            ["microsoft"] = new(
                config["Oidc:Microsoft:ClientId"] ?? "",
                "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration",
                null // Microsoft uses multiple issuers
            )
        };
    }

    public async Task<Result<OidcClaims>> ValidateAsync(string provider, string idToken, CancellationToken ct = default)
    {
        if (!_providers.TryGetValue(provider, out var providerConfig))
            return AppError.BadRequest($"Unsupported OIDC provider: {provider}");

        if (string.IsNullOrEmpty(providerConfig.ClientId))
            return AppError.ServiceUnavailable($"OIDC provider '{provider}' is not configured");

        try
        {
            var configManager = _configManagers.GetOrAdd(provider, _ =>
                new ConfigurationManager<OpenIdConnectConfiguration>(
                    providerConfig.MetadataUrl,
                    new OpenIdConnectConfigurationRetriever(),
                    new HttpDocumentRetriever()));

            var oidcConfig = await configManager.GetConfigurationAsync(ct);

            var validationParams = new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKeys = oidcConfig.SigningKeys,
                ValidateIssuer = providerConfig.Issuer is not null,
                ValidIssuer = providerConfig.Issuer,
                ValidateAudience = true,
                ValidAudience = providerConfig.ClientId,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(2)
            };

            var handler = new JwtSecurityTokenHandler();
            var principal = handler.ValidateToken(idToken, validationParams, out var validatedToken);

            var sub = principal.FindFirst("sub")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            var email = principal.FindFirst("email")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
            var name = principal.FindFirst("name")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            if (string.IsNullOrEmpty(sub) || string.IsNullOrEmpty(email))
                return AppError.Unauthorized("ID token missing required claims (sub, email)");

            return new OidcClaims(sub, email.ToLowerInvariant(), name);
        }
        catch (SecurityTokenException ex)
        {
            _logger.LogWarning(ex, "OIDC token validation failed for provider {Provider}", provider);
            return AppError.Unauthorized("Invalid or expired ID token");
        }
    }

    private record ProviderConfig(string ClientId, string MetadataUrl, string? Issuer);
}
