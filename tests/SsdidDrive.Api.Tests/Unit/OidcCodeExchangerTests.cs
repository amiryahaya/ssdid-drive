using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class OidcCodeExchangerTests
{
    [Fact]
    public void GetAuthorizationUrl_Google_ReturnsCorrectUrl()
    {
        var exchanger = CreateExchanger();

        var result = exchanger.GetAuthorizationUrl("google", "test-state-123");

        Assert.NotNull(result);
        var (url, state, codeVerifier) = result.Value;
        Assert.StartsWith("https://accounts.google.com/o/oauth2/v2/auth", url);
        Assert.Contains("client_id=google-client-id", url);
        Assert.Contains("response_type=code", url);
        Assert.Contains("scope=openid", url);
        Assert.Contains("state=test-state-123", url);
        Assert.Contains("code_challenge=", url);
        Assert.Contains("code_challenge_method=S256", url);
        Assert.Contains("redirect_uri=", url);
        Assert.Equal("test-state-123", state);
        Assert.False(string.IsNullOrEmpty(codeVerifier));
    }

    [Fact]
    public void GetAuthorizationUrl_Microsoft_ReturnsCorrectUrl()
    {
        var exchanger = CreateExchanger();

        var result = exchanger.GetAuthorizationUrl("microsoft", "ms-state");

        Assert.NotNull(result);
        var (url, state, codeVerifier) = result.Value;
        Assert.StartsWith("https://login.microsoftonline.com/common/oauth2/v2.0/authorize", url);
        Assert.Contains("client_id=microsoft-client-id", url);
        Assert.Contains("state=ms-state", url);
    }

    [Fact]
    public void GetAuthorizationUrl_UnsupportedProvider_ReturnsNull()
    {
        var exchanger = CreateExchanger();

        var result = exchanger.GetAuthorizationUrl("facebook", "state");

        Assert.Null(result);
    }

    [Fact]
    public void GetAuthorizationUrl_UnconfiguredProvider_ReturnsNull()
    {
        var config = new Dictionary<string, string?>
        {
            ["Oidc:Google:ClientId"] = "",
            ["Oidc:Google:ClientSecret"] = "",
            ["Oidc:Google:RedirectUri"] = "",
        };
        var exchanger = CreateExchanger(config);

        var result = exchanger.GetAuthorizationUrl("google", "state");

        Assert.Null(result);
    }

    [Fact]
    public void GetAuthorizationUrl_MissingRedirectUri_ReturnsNull()
    {
        var config = new Dictionary<string, string?>
        {
            ["Oidc:Google:ClientId"] = "google-client-id",
            ["Oidc:Google:ClientSecret"] = "google-client-secret",
            ["Oidc:Google:RedirectUri"] = "",
        };
        var exchanger = CreateExchanger(config);

        var result = exchanger.GetAuthorizationUrl("google", "state");

        Assert.Null(result);
    }

    [Fact]
    public void GetAuthorizationUrl_GeneratesUniquePkcePerCall()
    {
        var exchanger = CreateExchanger();

        var result1 = exchanger.GetAuthorizationUrl("google", "state1");
        var result2 = exchanger.GetAuthorizationUrl("google", "state2");

        Assert.NotNull(result1);
        Assert.NotNull(result2);
        Assert.NotEqual(result1.Value.CodeVerifier, result2.Value.CodeVerifier);
    }

    private static OidcCodeExchanger CreateExchanger(Dictionary<string, string?>? overrides = null)
    {
        var config = overrides ?? new Dictionary<string, string?>
        {
            ["Oidc:Google:ClientId"] = "google-client-id",
            ["Oidc:Google:ClientSecret"] = "google-client-secret",
            ["Oidc:Google:RedirectUri"] = "http://localhost:5000/api/auth/oidc/google/callback",
            ["Oidc:Microsoft:ClientId"] = "microsoft-client-id",
            ["Oidc:Microsoft:ClientSecret"] = "microsoft-client-secret",
            ["Oidc:Microsoft:RedirectUri"] = "http://localhost:5000/api/auth/oidc/microsoft/callback",
        };

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(config)
            .Build();

        return new OidcCodeExchanger(configuration, new HttpClient(),
            NullLogger<OidcCodeExchanger>.Instance);
    }
}
