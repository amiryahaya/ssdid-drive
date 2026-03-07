using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ShareTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public ShareTests(SsdidDriveFactory factory) => _factory = factory;

    #region Helpers

    /// <summary>
    /// Creates a second authenticated user in the same tenant as the first user.
    /// Required because GetFolder/ListFiles/DownloadFile all filter by TenantId,
    /// so share-based access only works within the same tenant.
    /// </summary>
    private static async Task<(HttpClient Client, Guid UserId)> CreateUserInTenantAsync(
        SsdidDriveFactory factory, Guid tenantId, string displayName = "Tenant Member")
    {
        var did = $"did:ssdid:test-{Guid.NewGuid():N}";
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<SessionStore>();

        var user = new User
        {
            Id = Guid.NewGuid(),
            Did = did,
            DisplayName = displayName,
            Status = UserStatus.Active,
            TenantId = tenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Users.Add(user);

        var userTenant = new UserTenant
        {
            UserId = user.Id,
            TenantId = tenantId,
            Role = TenantRole.Member,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.UserTenants.Add(userTenant);
        await db.SaveChangesAsync();

        sessionStore.CreateSessionDirect(did, sessionToken);

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id);
    }

    private static async Task<string> CreateFolderAsync(HttpClient client)
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Share Test Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        }, TestFixture.Json);
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetString()!;
    }

    private static async Task<string> UploadFileAsync(HttpClient client, string folderId,
        string fileName = "shared.bin", string content = "shared-encrypted-data")
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
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetString()!;
    }

    private static object MakeShareRequest(string resourceId, Guid sharedWithId,
        string resourceType = "folder", string permission = "read")
        => new
        {
            resource_id = Guid.Parse(resourceId),
            resource_type = resourceType,
            shared_with_id = sharedWithId,
            permission,
            encrypted_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        };

    private static async Task<(HttpStatusCode Status, JsonElement Body)> PostShareAsync(
        HttpClient client, object request)
    {
        var response = await client.PostAsJsonAsync("/api/shares", request, TestFixture.Json);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return (response.StatusCode, body);
    }

    #endregion

    // ── 1. CreateShare_Folder_ReturnsCreated ──────────────────────────

    [Fact]
    public async Task CreateShare_Folder_ReturnsCreated()
    {
        var (client1, userId1, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareOwner");
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "ShareRecipient");

        var folderId = await CreateFolderAsync(client1);

        var (status, body) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));

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

        var folderId = await CreateFolderAsync(client);

        var (status, _) = await PostShareAsync(client, MakeShareRequest(folderId, userId));

        Assert.Equal(HttpStatusCode.BadRequest, status);
    }

    // ── 3. CreateShare_DuplicateShare_Returns409 ──────────────────────

    [Fact]
    public async Task CreateShare_DuplicateShare_Returns409()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DupShareOwner");
        var (_, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "DupShareRecipient");

        var folderId = await CreateFolderAsync(client1);

        var (status1, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Created, status1);

        var (status2, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Conflict, status2);
    }

    // ── 4. CreateShare_NonOwner_Returns403 ────────────────────────────

    [Fact]
    public async Task CreateShare_NonOwner_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RealOwner");
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "NonOwner");

        // A third user to share with
        var (_, userId3) = await CreateUserInTenantAsync(_factory, tenantId, "ThirdUser");

        var folderId = await CreateFolderAsync(client1);

        // user2 (non-owner, no write share) tries to share user1's folder with user3
        var (status, _) = await PostShareAsync(client2, MakeShareRequest(folderId, userId3));

        Assert.Equal(HttpStatusCode.Forbidden, status);
    }

    // ── 5. ListCreatedShares_ReturnsSharesICreated ────────────────────

    [Fact]
    public async Task ListCreatedShares_ReturnsSharesICreated()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ListCreator");
        var (_, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "ListRecipient");

        var folderId = await CreateFolderAsync(client1);
        var (createStatus, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var response = await client1.GetAsync("/api/shares/created");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var shares = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
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
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "ReceivedRecipient");

        var folderId = await CreateFolderAsync(client1);
        var (createStatus, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var response = await client2.GetAsync("/api/shares/received");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var shares = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
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
        var (_, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "RevokeRecipient");

        var folderId = await CreateFolderAsync(client1);
        var (createStatus, createBody) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Created, createStatus);

        var shareId = createBody.GetProperty("id").GetString();

        var revokeResp = await client1.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Verify it's gone from created shares
        var listResp = await client1.GetAsync("/api/shares/created");
        var shares = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shareIds = Enumerable.Range(0, shares.GetArrayLength())
            .Select(i => shares[i].GetProperty("id").GetString())
            .ToList();
        Assert.DoesNotContain(shareId, shareIds);
    }

    // ── 8. RevokeShare_NonSharer_Returns403 ───────────────────────────

    [Fact]
    public async Task RevokeShare_NonSharer_Returns403()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeShareOwner");
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "RevokeShareRecipient");

        var folderId = await CreateFolderAsync(client1);
        var (createStatus, createBody) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
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
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "FileListRecipient");

        var folderId = await CreateFolderAsync(client1);
        await UploadFileAsync(client1, folderId, "shared-doc.bin", "secret-content");

        // Share folder with read access
        var (shareStatus, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
        Assert.Equal(HttpStatusCode.Created, shareStatus);

        // Recipient lists files in the shared folder
        var response = await client2.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var files = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
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
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "DownloadRecipient");

        var folderId = await CreateFolderAsync(client1);
        var fileContent = "top-secret-encrypted-data";
        var fileId = await UploadFileAsync(client1, folderId, "download-me.bin", fileContent);

        // Share folder
        var (shareStatus, _) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
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
        var (client2, userId2) = await CreateUserInTenantAsync(_factory, tenantId, "RevokeAccessRecipient");

        var folderId = await CreateFolderAsync(client1);

        // Share then revoke
        var (shareStatus, shareBody) = await PostShareAsync(client1, MakeShareRequest(folderId, userId2));
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

    // ── 12. CreateShare_WithoutAuth_Returns401 ────────────────────────

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
