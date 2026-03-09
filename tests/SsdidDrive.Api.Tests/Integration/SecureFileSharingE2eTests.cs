using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class SecureFileSharingE2eTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public SecureFileSharingE2eTests(SsdidDriveFactory factory) => _factory = factory;

    // ── Test 1: Full Secure File Sharing Workflow ────────────────────────

    [Fact]
    public async Task FullSecureFileSharingWorkflow()
    {
        // Setup: Alice creates tenant, Bob joins same tenant
        var (alice, aliceId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Alice-E2E");
        var (bob, bobId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Bob-E2E");

        // Step 1: Alice creates a folder
        var folderId = await TestFixture.CreateFolderAsync(alice, "Alice Secret Folder");

        // Step 2: Alice uploads an encrypted file
        var fileContent = "alice-top-secret-encrypted-payload";
        var fileId = await TestFixture.UploadFileAsync(alice, folderId, "secret.bin", fileContent);

        // Step 3: Bob CANNOT access folder or download file before sharing
        var bobFolderBefore = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobFolderBefore.StatusCode == HttpStatusCode.Forbidden ||
            bobFolderBefore.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not access folder before share, got {(int)bobFolderBefore.StatusCode}");

        var bobDownloadBefore = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.True(
            bobDownloadBefore.StatusCode == HttpStatusCode.Forbidden ||
            bobDownloadBefore.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not download file before share, got {(int)bobDownloadBefore.StatusCode}");

        // Step 4: Alice shares folder with Bob (read permission)
        var (shareStatus, shareBody) = await TestFixture.CreateShareAsync(alice, folderId, bobId, "read");
        Assert.Equal(HttpStatusCode.Created, shareStatus);
        var shareId = shareBody.GetProperty("id").GetString()!;

        // Step 5: Bob sees share in /shares/received with encrypted_key
        var receivedResp = await bob.GetAsync("/api/shares/received");
        Assert.Equal(HttpStatusCode.OK, receivedResp.StatusCode);
        var receivedBody = await receivedResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var receivedShares = receivedBody.GetProperty("items");
        var bobShare = Enumerable.Range(0, receivedShares.GetArrayLength())
            .Select(i => receivedShares[i])
            .First(s => s.GetProperty("resource_id").GetString() == folderId);
        Assert.False(string.IsNullOrEmpty(bobShare.GetProperty("encrypted_key").GetString()),
            "Received share should contain encrypted_key");

        // Step 6: Bob CAN now access folder, list files, and download
        var bobFolderAfter = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, bobFolderAfter.StatusCode);

        var bobFilesResp = await bob.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, bobFilesResp.StatusCode);
        var bobFilesBody = await bobFilesResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var bobFiles = bobFilesBody.GetProperty("items");
        Assert.True(bobFiles.GetArrayLength() >= 1, "Bob should see at least one file");
        var fileNames = Enumerable.Range(0, bobFiles.GetArrayLength())
            .Select(i => bobFiles[i].GetProperty("name").GetString())
            .ToList();
        Assert.Contains("secret.bin", fileNames);

        var bobDownloadAfter = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, bobDownloadAfter.StatusCode);
        var downloadedContent = await bobDownloadAfter.Content.ReadAsStringAsync();
        Assert.Equal(fileContent, downloadedContent);

        // Step 7: Alice revokes the share
        var revokeResp = await alice.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Step 8: Bob can NO LONGER access folder or download file
        var bobFolderRevoked = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobFolderRevoked.StatusCode == HttpStatusCode.Forbidden ||
            bobFolderRevoked.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not access folder after revoke, got {(int)bobFolderRevoked.StatusCode}");

        var bobDownloadRevoked = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.True(
            bobDownloadRevoked.StatusCode == HttpStatusCode.Forbidden ||
            bobDownloadRevoked.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not download file after revoke, got {(int)bobDownloadRevoked.StatusCode}");

        // Step 9: Alice can STILL access her own folder and file
        var aliceFolderAfter = await alice.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, aliceFolderAfter.StatusCode);

        var aliceDownloadAfter = await alice.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, aliceDownloadAfter.StatusCode);
        var aliceContent = await aliceDownloadAfter.Content.ReadAsStringAsync();
        Assert.Equal(fileContent, aliceContent);
    }

    // ── Test 2: Write ShareHolder Can Upload to Shared Folder ───────────

    [Fact]
    public async Task WriteShareHolder_CanUploadToSharedFolder()
    {
        // Setup: Alice creates tenant, Bob joins same tenant
        var (alice, aliceId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Alice-Write");
        var (bob, bobId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Bob-Write");

        // Step 1: Alice creates a folder
        var folderId = await TestFixture.CreateFolderAsync(alice, "Alice Write-Share Folder");

        // Step 2: Alice shares with Bob (WRITE permission)
        var (shareStatus, _) = await TestFixture.CreateShareAsync(alice, folderId, bobId, "write");
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Step 3: Bob uploads a file to Alice's folder
        var bobFileContent = "bob-uploaded-encrypted-data";
        var bobFileId = await TestFixture.UploadFileAsync(bob, folderId, "bob-file.bin", bobFileContent);
        Assert.False(string.IsNullOrEmpty(bobFileId), "Bob should get a file ID after upload");

        // Step 4: Alice can see Bob's file in the folder listing
        var aliceFilesResp = await alice.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, aliceFilesResp.StatusCode);
        var aliceFilesBody = await aliceFilesResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var aliceFiles = aliceFilesBody.GetProperty("items");
        var fileNames2 = Enumerable.Range(0, aliceFiles.GetArrayLength())
            .Select(i => aliceFiles[i].GetProperty("name").GetString())
            .ToList();
        Assert.Contains("bob-file.bin", fileNames2);
    }

    // ── Test 3: Read ShareHolder Cannot Upload to Shared Folder ─────────

    [Fact]
    public async Task ReadShareHolder_CannotUploadToSharedFolder()
    {
        // Setup: Alice creates tenant, Bob joins same tenant
        var (alice, aliceId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Alice-ReadOnly");
        var (bob, bobId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Bob-ReadOnly");

        // Step 1: Alice creates a folder
        var folderId = await TestFixture.CreateFolderAsync(alice, "Alice Read-Only Folder");

        // Step 2: Alice shares with Bob (READ permission)
        var (shareStatus, _) = await TestFixture.CreateShareAsync(alice, folderId, bobId, "read");
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Step 3: Bob tries to upload — should get 403
        var encKey = Convert.ToBase64String(Encoding.UTF8.GetBytes("test-file-key-0123456789abcdef"));
        var nonce = Convert.ToBase64String(new byte[12]);

        var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(Encoding.UTF8.GetBytes("bob-forbidden-data")), "file", "forbidden.bin");

        var url = $"/api/folders/{folderId}/files"
            + $"?encrypted_file_key={Uri.EscapeDataString(encKey)}"
            + $"&nonce={Uri.EscapeDataString(nonce)}"
            + $"&encryption_algorithm=AES-256-GCM";

        var response = await bob.PostAsync(url, form);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
