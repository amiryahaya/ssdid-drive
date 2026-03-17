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

    private static object MakeFolderRequest(string name = "Test Folder", Guid? parentFolderId = null)
        => new { name, parent_id = parentFolderId?.ToString() };

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
        return body.GetProperty("data").GetProperty("id").GetGuid();
    }

    #endregion

    [Fact]
    public async Task CreateFolder_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var (status, body) = await PostFolder(client, MakeFolderRequest("My Documents"));

        Assert.Equal(HttpStatusCode.Created, status);
        var data = body.GetProperty("data");
        Assert.Equal("My Documents", data.GetProperty("name").GetString());
        Assert.Equal(userId, data.GetProperty("owner_id").GetGuid());
    }

    [Fact]
    public async Task CreateFolder_EmptyName_AcceptsWithDefaultName()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var (status, body) = await PostFolder(client, MakeFolderRequest(name: ""));

        // Empty name is accepted — endpoint uses "encrypted" as default if name is null,
        // empty string is stored as-is
        Assert.Equal(HttpStatusCode.Created, status);
    }

    [Fact]
    public async Task CreateFolder_WithParent_Succeeds()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var parentId = await CreateFolderAndGetId(client, "Parent");
        var (status, body) = await PostFolder(client, MakeFolderRequest("Child", parentId));

        Assert.Equal(HttpStatusCode.Created, status);
        var data = body.GetProperty("data");
        Assert.Equal(parentId, data.GetProperty("parent_id").GetGuid());
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
        var data = body.GetProperty("data");
        Assert.Equal("Get Me", data.GetProperty("name").GetString());
        Assert.Equal(folderId, data.GetProperty("id").GetGuid());
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
    public async Task CreateFolder_MinimalRequest_Succeeds()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        // The new endpoint does not require encrypted_folder_key or kem_algorithm
        var request = new { name = "No Key Folder" };

        var response = await client.PostAsJsonAsync("/api/folders", request, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
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

        var response = await client.PostAsJsonAsync("/api/folders", new { name = "Test" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    #region GetFolderKey

    [Fact]
    public async Task GetFolderKey_Owner_ReturnsEncryptedKey()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FolderKeyOwner");
        var encKey = Convert.ToBase64String(new byte[32]);

        var folderId = await CreateFolderAndGetId(client, "KeyFolder");

        // Set the key via rotate-key (initial version becomes 2)
        var rotateResp = await client.PostAsJsonAsync($"/api/folders/{folderId}/rotate-key", new
        {
            encrypted_folder_key = encKey,
            kem_algorithm = "ML-KEM-768",
            member_keys = Array.Empty<object>()
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, rotateResp.StatusCode);

        var keyResponse = await client.GetAsync($"/api/folders/{folderId}/key");
        Assert.Equal(HttpStatusCode.OK, keyResponse.StatusCode);

        var body = await keyResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(encKey, body.GetProperty("encrypted_folder_key").GetString());
        Assert.Equal("ML-KEM-768", body.GetProperty("kem_algorithm").GetString());
        Assert.Equal(2, body.GetProperty("folder_key_version").GetInt32());
    }

    [Fact]
    public async Task GetFolderKey_NonOwnerNoShare_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KeyOwner2");

        var folderId = await CreateFolderAndGetId(client1, "PrivateFolder");

        // Different user in same tenant
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NoShareUser");
        var response = await client2.GetAsync($"/api/folders/{folderId}/key");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetFolderKey_SharedUser_ReturnsShareEncryptedKey()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareKeyOwner");

        var folderId = await CreateFolderAndGetId(client1, "SharedKeyFolder");

        // Create a second user in same tenant and share with them
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "SharedKeyUser");

        var (shareStatus, _) = await TestFixture.CreateShareAsync(client1, folderId.ToString(), userId2);
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        var keyResponse = await client2.GetAsync($"/api/folders/{folderId}/key");
        Assert.Equal(HttpStatusCode.OK, keyResponse.StatusCode);

        var body = await keyResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        // Share's encrypted_key is stored and returned
        Assert.NotNull(body.GetProperty("encrypted_folder_key").GetString());
        Assert.Equal("ML-KEM-768", body.GetProperty("kem_algorithm").GetString());
        Assert.Equal(1, body.GetProperty("folder_key_version").GetInt32());
    }

    [Fact]
    public async Task GetFolderKey_NonExistentFolder_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KeyNotFoundUser");

        var response = await client.GetAsync($"/api/folders/{Guid.NewGuid()}/key");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    #endregion

    #region RotateFolderKey

    [Fact]
    public async Task RotateFolderKey_Owner_IncrementsVersion()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RotateKeyOwner");

        var folderId = await CreateFolderAndGetId(client, "RotateFolder");

        var newKey = Convert.ToBase64String(new byte[48]);
        var rotateResponse = await client.PostAsJsonAsync($"/api/folders/{folderId}/rotate-key", new
        {
            encrypted_folder_key = newKey,
            kem_algorithm = "ML-KEM-1024",
            member_keys = Array.Empty<object>()
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, rotateResponse.StatusCode);

        var rotateBody = await rotateResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(2, rotateBody.GetProperty("folder_key_version").GetInt32());

        // Verify the key was updated
        var keyResponse = await client.GetAsync($"/api/folders/{folderId}/key");
        var keyBody = await keyResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(newKey, keyBody.GetProperty("encrypted_folder_key").GetString());
        Assert.Equal("ML-KEM-1024", keyBody.GetProperty("kem_algorithm").GetString());
        Assert.Equal(2, keyBody.GetProperty("folder_key_version").GetInt32());
    }

    [Fact]
    public async Task RotateFolderKey_NonOwner_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RotateOwner2");

        var folderId = await CreateFolderAndGetId(client1, "RotateProtected");

        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RotateNonOwner");
        var response = await client2.PostAsJsonAsync($"/api/folders/{folderId}/rotate-key", new
        {
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768",
            member_keys = Array.Empty<object>()
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RotateFolderKey_UpdatesMemberShareKeys()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RotateMemberOwner");

        var folderId = await CreateFolderAndGetId(client1, "RotateMemberFolder");

        // Create member and share
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RotateMember");
        var (shareStatus, _) = await TestFixture.CreateShareAsync(client1, folderId.ToString(), userId2);
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Rotate with member keys
        var newMemberKey = Convert.ToBase64String(new byte[64]);
        var rotateResponse = await client1.PostAsJsonAsync($"/api/folders/{folderId}/rotate-key", new
        {
            encrypted_folder_key = Convert.ToBase64String(new byte[48]),
            kem_algorithm = "ML-KEM-1024",
            member_keys = new[] { new { user_id = userId2, encrypted_key = newMemberKey } }
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, rotateResponse.StatusCode);

        // Verify member gets the updated key
        var keyResponse = await client2.GetAsync($"/api/folders/{folderId}/key");
        Assert.Equal(HttpStatusCode.OK, keyResponse.StatusCode);
        var keyBody = await keyResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(newMemberKey, keyBody.GetProperty("encrypted_folder_key").GetString());
        Assert.Equal("ML-KEM-1024", keyBody.GetProperty("kem_algorithm").GetString());
        Assert.Equal(2, keyBody.GetProperty("folder_key_version").GetInt32());
    }

    #endregion
}
