using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class WalletLoginFlowTests : IClassFixture<WalletLoginFlowTests.WalletLoginFactory>
{
    private readonly WalletLoginFactory _factory;

    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public WalletLoginFlowTests(WalletLoginFactory factory) => _factory = factory;

    [Fact]
    public async Task LoginInitiate_ReturnsQrPayload()
    {
        var client = _factory.CreateClient();
        var resp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var body = await resp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("challenge_id", out var challengeId));
        Assert.False(string.IsNullOrEmpty(challengeId.GetString()));

        Assert.True(body.TryGetProperty("qr_payload", out var qrPayload));
        var payload = qrPayload;
        Assert.Equal("login", payload.GetProperty("action").GetString());
        Assert.True(payload.TryGetProperty("challenge", out _));
        Assert.True(payload.TryGetProperty("server_did", out _));
        Assert.True(payload.TryGetProperty("server_key_id", out _));
        Assert.True(payload.TryGetProperty("server_signature", out _));
        Assert.True(payload.TryGetProperty("service_name", out _));
        Assert.True(payload.TryGetProperty("service_url", out _));
        Assert.True(payload.TryGetProperty("registry_url", out _));
    }

    public class WalletLoginFactory : SsdidDriveFactory
    {
        public MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.AddHttpClient<RegistryClient>()
                    .ConfigurePrimaryHttpMessageHandler(() => MockRegistryHandler);
            });
        }
    }

    public class MockRegistryDelegatingHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, object> _documents = new();

        public void RegisterDid(string did, Dictionary<string, object> didDocument)
        {
            _documents[did] = new { did_document = didDocument };
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct)
        {
            var path = request.RequestUri?.AbsolutePath ?? "";

            if (request.Method == HttpMethod.Post && path == "/api/did")
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Created)
                {
                    Content = new StringContent("{}", Encoding.UTF8, "application/json")
                });
            }

            if (request.Method == HttpMethod.Get && path.StartsWith("/api/did/"))
            {
                var encodedDid = path["/api/did/".Length..];
                var did = Uri.UnescapeDataString(encodedDid);

                if (_documents.TryGetValue(did, out var doc))
                {
                    var json = JsonSerializer.Serialize(doc);
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                    {
                        Content = new StringContent(json, Encoding.UTF8, "application/json")
                    });
                }

                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }
}
