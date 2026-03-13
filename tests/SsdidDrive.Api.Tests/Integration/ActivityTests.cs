using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ActivityTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public ActivityTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task ListActivity_ReturnsEmptyPagedResponse()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ActivityUser");
        var response = await client.GetAsync("/api/activity");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var items));
        Assert.Equal(0, items.GetArrayLength());
        Assert.True(body.TryGetProperty("total", out _));
        Assert.True(body.TryGetProperty("page", out _));
        Assert.True(body.TryGetProperty("page_size", out _));
    }

    [Fact]
    public async Task ListActivity_PaginationDefaults()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ActivityPager");
        var response = await client.GetAsync("/api/activity");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(1, body.GetProperty("page").GetInt32());
        Assert.Equal(50, body.GetProperty("page_size").GetInt32());
    }

    [Fact]
    public async Task ListResourceActivity_NotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ResActivityUser");
        var response = await client.GetAsync($"/api/activity/resource/{Guid.NewGuid()}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AdminActivity_NonAdminMember_Returns403()
    {
        // CreateAuthenticatedClientAsync creates user as Owner — we need a Member
        var (_, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminOwner");
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RegularActivityUser");

        var response = await memberClient.GetAsync("/api/activity/admin");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task AdminActivity_OwnerRole_ReturnsOk()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminActivityOwner");
        var response = await client.GetAsync("/api/activity/admin");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out _));
        Assert.True(body.TryGetProperty("total", out _));
    }
}
