using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class FolderTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public FolderTests(SsdidDriveFactory factory) => _factory = factory;

    #region Helpers

    private static object MakeFolderRequest(string name = "Test Folder", Guid? parentFolderId = null,
        string encryptedFolderKey = "dGVzdC1rZXk=", string kemAlgorithm = "ML-KEM-768")
        => new { name, parent_folder_id = parentFolderId, encrypted_folder_key = encryptedFolderKey, kem_algorithm = kemAlgorithm };

    private static async Task<(HttpStatusCode Status, JsonElement Body)> PostFolder(
        HttpClient client, object request)
    {
        var response = await client.PostAsJsonAsync("/api/folders", request, TestFixture.Json);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return (response.StatusCode, body);
    }

    private static async Task<Guid> CreateFolderAndGetId(HttpClient client, string name = "Test Folder", Guid? parentFolderId = null)
    {
        var (status, body) = await PostFolder(client, MakeFolderRequest(name, parentFolderId));
        Assert.Equal(HttpStatusCode.Created, status);
        return body.GetProperty("id").GetGuid();
    }

    #endregion

    [Fact]
    public async Task CreateFolder_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var (status, body) = await PostFolder(client, MakeFolderRequest("My Documents"));

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal("My Documents", body.GetProperty("name").GetString());
        Assert.Equal("ML-KEM-768", body.GetProperty("kem_algorithm").GetString());
        Assert.Equal(userId, body.GetProperty("owner_id").GetGuid());
    }

    [Fact]
    public async Task CreateFolder_EmptyName_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var (status, _) = await PostFolder(client, MakeFolderRequest(name: ""));

        Assert.Equal(HttpStatusCode.BadRequest, status);
    }

    [Fact]
    public async Task CreateFolder_WithParent_Succeeds()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var parentId = await CreateFolderAndGetId(client, "Parent");
        var (status, body) = await PostFolder(client, MakeFolderRequest("Child", parentId));

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal(parentId, body.GetProperty("parent_folder_id").GetGuid());
    }

    [Fact]
    public async Task CreateFolder_NonExistentParent_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var (status, _) = await PostFolder(client, MakeFolderRequest("Orphan", Guid.NewGuid()));

        Assert.Equal(HttpStatusCode.NotFound, status);
    }

    [Fact]
    public async Task ListFolders_ReturnsOwnedFolders()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await CreateFolderAndGetId(client, "Folder A");
        await CreateFolderAndGetId(client, "Folder B");

        var response = await client.GetAsync("/api/folders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var folders = body.GetProperty("items");
        Assert.True(folders.GetArrayLength() >= 2);

        var names = Enumerable.Range(0, folders.GetArrayLength())
            .Select(i => folders[i].GetProperty("name").GetString())
            .ToList();
        Assert.Contains("Folder A", names);
        Assert.Contains("Folder B", names);
    }

    [Fact]
    public async Task ListFolders_ExcludesOtherUserFolders()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "User1");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "User2");

        await CreateFolderAndGetId(client1, "Private Folder");

        var response = await client2.GetAsync("/api/folders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var folders = body.GetProperty("items");
        Assert.Equal(0, folders.GetArrayLength());
    }

    [Fact]
    public async Task GetFolder_ReturnsFolder()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var folderId = await CreateFolderAndGetId(client, "Get Me");

        var response = await client.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Get Me", body.GetProperty("name").GetString());
        Assert.Equal(folderId, body.GetProperty("id").GetGuid());
    }

    [Fact]
    public async Task GetFolder_OtherUserFolder_Returns403Or404()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Intruder");

        var folderId = await CreateFolderAndGetId(client1, "Secret Folder");

        var response = await client2.GetAsync($"/api/folders/{folderId}");

        // Different tenants → tenant filter yields 404; same tenant would yield 403
        Assert.True(
            response.StatusCode == HttpStatusCode.Forbidden || response.StatusCode == HttpStatusCode.NotFound,
            $"Expected 403 or 404 but got {(int)response.StatusCode}");
    }

    [Fact]
    public async Task DeleteFolder_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var folderId = await CreateFolderAndGetId(client, "Delete Me");

        var deleteResp = await client.DeleteAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResp.StatusCode);

        var getResp = await client.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.NotFound, getResp.StatusCode);
    }

    [Fact]
    public async Task DeleteFolder_NonOwner_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DelFolderOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "DelFolderNonOwner");

        var folderId = await CreateFolderAndGetId(client1, "Protected Folder");

        var response = await client2.DeleteAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task DeleteFolder_CascadesSubFolders()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var parentId = await CreateFolderAndGetId(client, "Parent");
        var childId = await CreateFolderAndGetId(client, "Child", parentId);

        var deleteResp = await client.DeleteAsync($"/api/folders/{parentId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResp.StatusCode);

        var parentGet = await client.GetAsync($"/api/folders/{parentId}");
        Assert.Equal(HttpStatusCode.NotFound, parentGet.StatusCode);

        var childGet = await client.GetAsync($"/api/folders/{childId}");
        Assert.Equal(HttpStatusCode.NotFound, childGet.StatusCode);
    }

    [Fact]
    public async Task CreateFolder_MissingEncryptedFolderKey_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var request = new
        {
            name = "No Key Folder",
            encrypted_folder_key = "",
            kem_algorithm = "ML-KEM-768"
        };

        var response = await client.PostAsJsonAsync("/api/folders", request, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task DeleteFolder_CascadesFiles()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var folderId = await CreateFolderAndGetId(client, "CascadeFileFolder");
        var fileId = await TestFixture.UploadFileAsync(client, folderId.ToString(), "cascade-file.bin");

        var deleteResp = await client.DeleteAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResp.StatusCode);

        // Verify folder is gone
        var folderGet = await client.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.NotFound, folderGet.StatusCode);

        // Verify file is gone too
        var fileGet = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.NotFound, fileGet.StatusCode);
    }

    [Fact]
    public async Task CreateFolder_WithoutAuth_Returns401()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/folders", MakeFolderRequest(), TestFixture.Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
