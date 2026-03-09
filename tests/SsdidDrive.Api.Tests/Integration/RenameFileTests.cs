using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class RenameFileTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public RenameFileTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RenameFile_ValidName_ReturnsOkWithUpdatedFile()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Rename Test Folder");
        var fileId = await TestFixture.UploadFileAsync(client, folderId, "original.bin");

        var response = await client.PatchAsJsonAsync(
            $"/api/files/{fileId}",
            new { name = "renamed.bin" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("renamed.bin", body.GetProperty("name").GetString());
        Assert.Equal(fileId, body.GetProperty("id").GetString());
        Assert.Equal(userId, body.GetProperty("uploaded_by_id").GetGuid());
    }

    [Fact]
    public async Task RenameFile_NonUploader_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Uploader");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "OtherUser");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Owner Folder");
        var fileId = await TestFixture.UploadFileAsync(client1, folderId, "private.bin");

        var response = await client2.PatchAsJsonAsync(
            $"/api/files/{fileId}",
            new { name = "hijacked.bin" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RenameFile_EmptyName_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Test Folder");
        var fileId = await TestFixture.UploadFileAsync(client, folderId, "test.bin");

        var response = await client.PatchAsJsonAsync(
            $"/api/files/{fileId}",
            new { name = "" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task RenameFile_NonExistent_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PatchAsJsonAsync(
            $"/api/files/{Guid.NewGuid()}",
            new { name = "ghost.bin" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
