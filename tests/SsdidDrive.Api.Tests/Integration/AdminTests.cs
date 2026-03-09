using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public AdminTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AdminStats_NonAdmin_Returns403()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RegularUser");
        var response = await client.GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task AdminStats_SuperAdmin_ReturnsStats()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminUser", systemRole: "SuperAdmin");
        var response = await client.GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("user_count", out _));
        Assert.True(body.TryGetProperty("tenant_count", out _));
        Assert.True(body.TryGetProperty("file_count", out _));
        Assert.True(body.TryGetProperty("total_storage_bytes", out _));
        Assert.True(body.TryGetProperty("active_session_count", out _));
    }
}
