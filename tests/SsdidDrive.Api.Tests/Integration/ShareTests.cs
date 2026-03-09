using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ShareTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public ShareTests(SsdidDriveFactory factory) => _factory = factory;

    // ── 1. CreateShare_Folder_ReturnsCreated ──────────────────────────

    [Fact]
    public async Task CreateShare_Folder_ReturnsCreated()
    {
        var (client1, userId1, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ShareRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");

        var (status, body) = await TestFixture.CreateShareAsync(client1, folderId, userId2);

        Assert.Equal(HttpStatusCode.Created, status);
        Assert.Equal(folderId, body.GetProperty("resource_id").GetString());
        Assert.Equal("folder", body.GetProperty("resource_type").GetString());
        Assert.Equal("read", body.GetProperty("permission").GetString());
        Assert.Equal(userId1, body.GetProperty("shared_by_id").GetGuid());
        Assert.Equal(userId2, body.GetProperty("shared_with_id").GetGuid());
    }

    // ── 2. CreateShare_SelfShare_Returns400 ───────────────────────────

    [Fact]
    public async Task CreateShare_SelfShare_Returns400()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SelfSharer");

        var folderId = await TestFixture.CreateFolderAsync(client, "Share Test Folder");

        var (status, _) = await TestFixture.CreateShareAsync(client, folderId, userId);

        Assert.Equal(HttpStatusCode.BadRequest, status);
    }

    // ── 3. CreateShare_DuplicateShare_Returns409 ──────────────────────

    [Fact]
    public async Task CreateShare_DuplicateShare_Returns409()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DupShareOwner");
        var (_, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "DupShareRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");

        var (status1, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, status1);

        var (status2, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Conflict, status2);
    }

    // ── 4. CreateShare_NonOwner_Returns403 ────────────────────────────

    [Fact]
    public async Task CreateShare_NonOwner_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RealOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NonOwner");

        // A third user to share with
        var (_, userId3) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ThirdUser");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");

        // user2 (non-owner, no write share) tries to share user1's folder with user3
        var (status, _) = await TestFixture.CreateShareAsync(client2, folderId, userId3);

        Assert.Equal(HttpStatusCode.Forbidden, status);
    }

    // ── 5. ListCreatedShares_ReturnsSharesICreated ────────────────────

    [Fact]
    public async Task ListCreatedShares_ReturnsSharesICreated()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ListCreator");
        var (_, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ListRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        var (createStatus, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var response = await client1.GetAsync("/api/shares/created");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var sharesBody = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shares = sharesBody.GetProperty("items");
        Assert.True(shares.GetArrayLength() >= 1);

        var resourceIds = Enumerable.Range(0, shares.GetArrayLength())
            .Select(i => shares[i].GetProperty("resource_id").GetString())
            .ToList();
        Assert.Contains(folderId, resourceIds);
    }

    // ── 6. ListReceivedShares_ReturnsSharesSharedWithMe ───────────────

    [Fact]
    public async Task ListReceivedShares_ReturnsSharesSharedWithMe()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ReceivedOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ReceivedRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        var (createStatus, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var response = await client2.GetAsync("/api/shares/received");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var sharesBody = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shares = sharesBody.GetProperty("items");
        Assert.True(shares.GetArrayLength() >= 1);

        // Find the share for our folder
        var share = Enumerable.Range(0, shares.GetArrayLength())
            .Select(i => shares[i])
            .First(s => s.GetProperty("resource_id").GetString() == folderId);

        // encrypted_key should be present in received shares
        Assert.False(string.IsNullOrEmpty(share.GetProperty("encrypted_key").GetString()));
    }

    // ── 7. RevokeShare_ReturnsNoContent ───────────────────────────────

    [Fact]
    public async Task RevokeShare_ReturnsNoContent()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeOwner");
        var (_, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RevokeRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        var (createStatus, createBody) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var shareId = createBody.GetProperty("id").GetString();

        var revokeResp = await client1.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Verify it's gone from created shares
        var listResp = await client1.GetAsync("/api/shares/created");
        var sharesBody2 = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shares2 = sharesBody2.GetProperty("items");
        var shareIds = Enumerable.Range(0, shares2.GetArrayLength())
            .Select(i => shares2[i].GetProperty("id").GetString())
            .ToList();
        Assert.DoesNotContain(shareId, shareIds);
    }

    // ── 8. RevokeShare_NonSharer_Returns403 ───────────────────────────

    [Fact]
    public async Task RevokeShare_NonSharer_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeShareOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RevokeShareRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        var (createStatus, createBody) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var shareId = createBody.GetProperty("id").GetString();

        // Recipient (not the sharer) tries to revoke
        var revokeResp = await client2.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.Forbidden, revokeResp.StatusCode);
    }

    // ── 9. SharedFolder_RecipientCanListFiles ─────────────────────────

    [Fact]
    public async Task SharedFolder_RecipientCanListFiles()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FileListOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "FileListRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        await TestFixture.UploadFileAsync(client1, folderId, "shared-doc.bin", "secret-content");

        // Share folder with read access
        var (shareStatus, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Recipient lists files in the shared folder
        var response = await client2.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var filesBody = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var files = filesBody.GetProperty("items");
        Assert.True(files.GetArrayLength() >= 1);

        var names = Enumerable.Range(0, files.GetArrayLength())
            .Select(i => files[i].GetProperty("name").GetString())
            .ToList();
        Assert.Contains("shared-doc.bin", names);
    }

    // ── 10. SharedFolder_RecipientCanDownloadFile ─────────────────────

    [Fact]
    public async Task SharedFolder_RecipientCanDownloadFile()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DownloadOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "DownloadRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");
        var fileContent = "top-secret-encrypted-data";
        var fileId = await TestFixture.UploadFileAsync(client1, folderId, "download-me.bin", fileContent);

        // Share folder
        var (shareStatus, _) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Recipient downloads the file
        var response = await client2.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var downloadedContent = await response.Content.ReadAsStringAsync();
        Assert.Equal(fileContent, downloadedContent);
    }

    // ── 11. RevokedShare_RecipientCannotAccessFolder ──────────────────

    [Fact]
    public async Task RevokedShare_RecipientCannotAccessFolder()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeAccessOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RevokeAccessRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Test Folder");

        // Share then revoke
        var (shareStatus, shareBody) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        var shareId = shareBody.GetProperty("id").GetString();

        // Verify recipient can access before revoke
        var accessBefore = await client2.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, accessBefore.StatusCode);

        // Revoke the share
        var revokeResp = await client1.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Recipient should no longer have access
        var accessAfter = await client2.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            accessAfter.StatusCode == HttpStatusCode.Forbidden || accessAfter.StatusCode == HttpStatusCode.NotFound,
            $"Expected 403 or 404 but got {(int)accessAfter.StatusCode}");
    }

    // ── 12. CreateShare_MissingEncryptedKey_Returns400 ────────────────

    [Fact]
    public async Task CreateShare_MissingEncryptedKey_Returns400()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareMissingKeyOwner");
        var (_, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ShareMissingKeyRecipient");

        var folderId = await TestFixture.CreateFolderAsync(client1, "Share Missing Key Folder");

        var request = new
        {
            resource_id = Guid.Parse(folderId),
            resource_type = "folder",
            shared_with_id = userId2,
            permission = "read",
            encrypted_key = "",  // Missing/empty
            kem_algorithm = "ML-KEM-768"
        };

        var response = await client1.PostAsJsonAsync("/api/shares", request, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 13. CreateShare_WithoutAuth_Returns401 ────────────────────────

    [Fact]
    public async Task CreateShare_WithoutAuth_Returns401()
    {
        var client = _factory.CreateClient();

        var request = new
        {
            resource_id = Guid.NewGuid(),
            resource_type = "folder",
            shared_with_id = Guid.NewGuid(),
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        };

        var response = await client.PostAsJsonAsync("/api/shares", request, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
