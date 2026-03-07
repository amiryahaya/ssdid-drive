using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class FileTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public FileTests(SsdidDriveFactory factory) => _factory = factory;

    #region Helpers

    private static async Task<string> CreateFolderAsync(HttpClient client)
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Test Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        }, TestFixture.Json);
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetString()!;
    }

    private static async Task<(HttpStatusCode Status, JsonElement Body)> UploadFileAsync(
        HttpClient client,
        string folderId,
        string fileName = "test.bin",
        string content = "encrypted-content")
    {
        var encKey = Convert.ToBase64String(Encoding.UTF8.GetBytes("test-file-key-0123456789abcdef"));
        var nonce = Convert.ToBase64String(new byte[12]);

        var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(Encoding.UTF8.GetBytes(content)), "file", fileName);

        var url = $"/api/folders/{folderId}/files"
            + $"?encrypted_file_key={Uri.EscapeDataString(encKey)}"
            + $"&nonce={Uri.EscapeDataString(nonce)}"
            + $"&encryption_algorithm=AES-256-GCM";

        var response = await client.PostAsync(url, form);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return (response.StatusCode, body);
    }

    private static async Task<string> UploadFileAndGetIdAsync(
        HttpClient client, string folderId, string fileName = "test.bin", string content = "encrypted-content")
    {
        var (status, body) = await UploadFileAsync(client, folderId, fileName, content);
        Assert.Equal(HttpStatusCode.Created, status);
        return body.GetProperty("id").GetString()!;
    }

    #endregion

    [Fact]
    public async Task UploadFile_ReturnsCreated()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        var (status, body) = await UploadFileAsync(client, folderId, "document.bin", "my-encrypted-data");

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal("document.bin", body.GetProperty("name").GetString());
        Assert.Equal(Encoding.UTF8.GetBytes("my-encrypted-data").Length, body.GetProperty("size").GetInt64());
        Assert.Equal("AES-256-GCM", body.GetProperty("encryption_algorithm").GetString());
    }

    [Fact]
    public async Task UploadFile_NonExistentFolder_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var randomFolderId = Guid.NewGuid().ToString();

        var (status, _) = await UploadFileAsync(client, randomFolderId);

        Assert.Equal(HttpStatusCode.NotFound, status);
    }

    [Fact]
    public async Task ListFiles_ReturnsFilesInFolder()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        await UploadFileAndGetIdAsync(client, folderId, "file1.bin", "content-1");
        await UploadFileAndGetIdAsync(client, folderId, "file2.bin", "content-2");

        var response = await client.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var files = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(2, files.GetArrayLength());
    }

    [Fact]
    public async Task DownloadFile_ReturnsFileContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);
        var originalContent = "my-secret-encrypted-data";

        var fileId = await UploadFileAndGetIdAsync(client, folderId, "secret.bin", originalContent);

        var response = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var downloadedContent = await response.Content.ReadAsStringAsync();
        Assert.Equal(originalContent, downloadedContent);
    }

    [Fact]
    public async Task DownloadFile_OtherUser_Returns403Or404()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Uploader");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Outsider");

        var folderId = await CreateFolderAsync(client1);
        var fileId = await UploadFileAndGetIdAsync(client1, folderId, "private.bin");

        var response = await client2.GetAsync($"/api/files/{fileId}/download");

        Assert.True(
            response.StatusCode == HttpStatusCode.Forbidden || response.StatusCode == HttpStatusCode.NotFound,
            $"Expected 403 or 404 but got {(int)response.StatusCode}");
    }

    [Fact]
    public async Task DeleteFile_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);
        var fileId = await UploadFileAndGetIdAsync(client, folderId, "deleteme.bin");

        var deleteResp = await client.DeleteAsync($"/api/files/{fileId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResp.StatusCode);

        var downloadResp = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.NotFound, downloadResp.StatusCode);
    }

    [Fact]
    public async Task DeleteFile_NonOwner_Returns403()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FileOwner");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NonOwner");

        var folderId = await CreateFolderAsync(client1);
        var fileId = await UploadFileAndGetIdAsync(client1, folderId, "protected.bin");

        var response = await client2.DeleteAsync($"/api/files/{fileId}");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task UploadFile_WithoutAuth_Returns401()
    {
        var client = _factory.CreateClient();

        var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(Encoding.UTF8.GetBytes("data")), "file", "test.bin");

        var encKey = Convert.ToBase64String(new byte[16]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{Guid.NewGuid()}/files"
            + $"?encrypted_file_key={Uri.EscapeDataString(encKey)}"
            + $"&nonce={Uri.EscapeDataString(nonce)}"
            + $"&encryption_algorithm=AES-256-GCM";

        var response = await client.PostAsync(url, form);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
