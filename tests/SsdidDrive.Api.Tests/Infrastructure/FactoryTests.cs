namespace SsdidDrive.Api.Tests.Infrastructure;

public class FactoryTests : IClassFixture<SsdidDriveFactory>
{
    private readonly HttpClient _client;
    private readonly SsdidDriveFactory _factory;

    public FactoryTests(SsdidDriveFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task HealthEndpoint_ReturnsOk()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_WithoutAuth_Returns401()
    {
        var response = await _client.GetAsync("/api/me");
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task AuthenticatedClient_CanAccessProtectedEndpoint()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var response = await client.GetAsync("/api/me");
        Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
    }
}
