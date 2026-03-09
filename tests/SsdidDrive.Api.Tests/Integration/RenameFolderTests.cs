using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class RenameFolderTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public RenameFolderTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RenameFolder_ValidName_ReturnsOkWithUpdatedFolder()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Original Name");

        var response = await client.PatchAsJsonAsync(
            $"/api/folders/{folderId}",
            new { name = "Renamed Folder" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Renamed Folder", body.GetProperty("name").GetString());
        Assert.Equal(folderId, body.GetProperty("id").GetString());
        Assert.Equal(userId, body.GetProperty("owner_id").GetGuid());
    }

    [Fact]
    public async Task RenameFolder_NonOwner_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NonOwner");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Owner's Folder");

        var response = await client2.PatchAsJsonAsync(
            $"/api/folders/{folderId}",
            new { name = "Hijacked" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RenameFolder_EmptyName_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Will Rename");

        var response = await client.PatchAsJsonAsync(
            $"/api/folders/{folderId}",
            new { name = "" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task RenameFolder_NonExistent_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PatchAsJsonAsync(
            $"/api/folders/{Guid.NewGuid()}",
            new { name = "Ghost Folder" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
