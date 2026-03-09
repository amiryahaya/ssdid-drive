using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// End-to-end tests simulating wallet ↔ drive client interactions.
/// These test the full journey: wallet authentication → drive operations.
/// </summary>
public class WalletDriveE2eTests : IClassFixture<WalletDriveE2eTests.WalletDriveFactory>
{
    private readonly WalletDriveFactory _factory;

    public WalletDriveE2eTests(WalletDriveFactory factory) => _factory = factory;

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 1: New User Journey
    //   Wallet registers → SSE delivers session → first drive operations
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task NewUserJourney_WalletRegisterAndAuthenticate_CanPerformDriveOperations()
    {
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var client = _factory.CreateClient();

        // Step 1: Client initiates login (displays QR)
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        Assert.Equal(HttpStatusCode.OK, initResp.StatusCode);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        // Step 2: Client subscribes to SSE (background) — separate client avoids header mutation
        var sseClient = _factory.CreateClient();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var sseTask = TestFixture.ReadSseEventOrFail(sseClient, challengeId, subscriberSecret, cts.Token, "new user SSE");

        // Step 3: Wallet scans QR → registers with service
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // Step 4: Wallet authenticates with the credential + challengeId
        var walletClient = _factory.CreateClient();
        var authResp = await walletClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);

        // Step 5: Client receives session token via SSE
        var sseData = await sseTask;
        var sessionToken = sseData.GetProperty("session_token").GetString()!;

        // Step 6: Client uses session token for drive operations
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        // 6a: Check profile
        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
        var meBody = await meResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(walletIdentity.Did, meBody.GetProperty("did").GetString());

        // 6b: Create a folder
        var folderId = await TestFixture.CreateFolderAsync(client, "My First Folder");
        Assert.False(string.IsNullOrEmpty(folderId));

        // 6c: Upload a file
        var fileId = await TestFixture.UploadFileAsync(client, folderId, "hello.txt", "encrypted-content-hello");
        Assert.False(string.IsNullOrEmpty(fileId));

        // 6d: List files in folder
        var listResp = await client.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, listResp.StatusCode);
        var listBody = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = listBody.GetProperty("items");
        Assert.Equal(1, items.GetArrayLength());
        Assert.Equal("hello.txt", items[0].GetProperty("name").GetString());

        // 6e: Download the file
        var dlResp = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, dlResp.StatusCode);
        var dlContent = await dlResp.Content.ReadAsStringAsync();
        Assert.Equal("encrypted-content-hello", dlContent);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 2: Returning User Journey
    //   Pre-registered wallet → authenticate → file operations
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ReturningUserJourney_AlreadyRegisteredWallet_CanAuthenticate()
    {
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        // Pre-register the wallet
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // First login: establish presence and upload a file
        var session1 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);
        var client1 = _factory.CreateClient();
        client1.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session1);
        var folderId = await TestFixture.CreateFolderAsync(client1, "Returning User Folder");
        await TestFixture.UploadFileAsync(client1, folderId, "doc.pdf", "encrypted-pdf-data");

        // Second login: returning user authenticates again
        var session2 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);
        Assert.NotEqual(session1, session2); // New session each time

        var client2 = _factory.CreateClient();
        client2.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session2);

        // Returning user can access previously uploaded data
        var meResp = await client2.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);

        var filesResp = await client2.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, filesResp.StatusCode);
        var filesBody = await filesResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Contains("doc.pdf",
            Enumerable.Range(0, filesBody.GetProperty("items").GetArrayLength())
                .Select(i => filesBody.GetProperty("items")[i].GetProperty("name").GetString()));

        var docFileId = await GetFileId(client2, folderId, "doc.pdf");
        var dlResp = await client2.GetAsync($"/api/files/{docFileId}/download");
        Assert.Equal(HttpStatusCode.OK, dlResp.StatusCode);
        Assert.Equal("encrypted-pdf-data", await dlResp.Content.ReadAsStringAsync());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 3: Multi-User Sharing Flow
    //   Alice registers via wallet → creates + uploads → shares with Bob
    //   Bob registers via wallet → accesses shared content → Alice revokes
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task MultiUserSharingFlow_WalletUsersShareContent()
    {
        // Create two wallet identities
        var (aliceWallet, _) = TestFixture.CreateWalletIdentity();
        var (bobWallet, _) = TestFixture.CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(aliceWallet.Did, aliceWallet.BuildDidDocument());
        _factory.MockRegistryHandler.RegisterDid(bobWallet.Did, bobWallet.BuildDidDocument());

        // Alice registers and authenticates
        var aliceCred = await TestFixture.RegisterWalletAsync(_factory, aliceWallet);
        var aliceToken = await TestFixture.AuthenticateWalletViaSseAsync(_factory, aliceWallet, aliceCred);
        var alice = _factory.CreateClient();
        alice.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", aliceToken);

        // Bob registers and authenticates
        var bobCred = await TestFixture.RegisterWalletAsync(_factory, bobWallet);
        var bobToken = await TestFixture.AuthenticateWalletViaSseAsync(_factory, bobWallet, bobCred);
        var bob = _factory.CreateClient();
        bob.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", bobToken);

        // Add Bob to Alice's tenant so sharing is possible
        Guid bobUserId;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var aliceUser = await db.Users.FirstAsync(u => u.Did == aliceWallet.Did);
            var bobUser = await db.Users.FirstAsync(u => u.Did == bobWallet.Did);
            bobUserId = bobUser.Id;

            Assert.True(aliceUser.TenantId.HasValue,
                "SSDID registration must create a Tenant for the new user");
            var aliceTenantId = aliceUser.TenantId!.Value;

            bobUser.TenantId = aliceTenantId;
            db.UserTenants.Add(new SsdidDrive.Api.Data.Entities.UserTenant
            {
                UserId = bobUserId,
                TenantId = aliceTenantId,
                Role = SsdidDrive.Api.Data.Entities.TenantRole.Member,
                CreatedAt = DateTimeOffset.UtcNow
            });
            await db.SaveChangesAsync();
        }

        // Alice creates folder, uploads file
        var folderId = await TestFixture.CreateFolderAsync(alice, "Alice Shared Folder");
        var fileId = await TestFixture.UploadFileAsync(alice, folderId, "shared-doc.bin", "alice-encrypted-payload");

        // Bob CANNOT access before sharing
        var bobPreAccess = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobPreAccess.StatusCode == HttpStatusCode.Forbidden ||
            bobPreAccess.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not access folder before share, got {(int)bobPreAccess.StatusCode}");

        // Alice shares folder with Bob (read)
        var (shareStatus, shareBody) = await TestFixture.CreateShareAsync(alice, folderId, bobUserId);
        Assert.Equal(HttpStatusCode.Created, shareStatus);
        var shareId = shareBody.GetProperty("id").GetString()!;

        // Bob CAN now access the folder and download file
        var bobFolderResp = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, bobFolderResp.StatusCode);

        var bobDlResp = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, bobDlResp.StatusCode);
        Assert.Equal("alice-encrypted-payload", await bobDlResp.Content.ReadAsStringAsync());

        // Bob checks received shares
        var receivedResp = await bob.GetAsync("/api/shares/received");
        Assert.Equal(HttpStatusCode.OK, receivedResp.StatusCode);
        var receivedBody = await receivedResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var receivedItems = receivedBody.GetProperty("items");
        Assert.True(receivedItems.GetArrayLength() >= 1, "Bob should have at least one received share");

        // Alice revokes the share
        var revokeResp = await alice.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Bob can NO LONGER access folder OR download file
        var bobPostRevokeFolder = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobPostRevokeFolder.StatusCode == HttpStatusCode.Forbidden ||
            bobPostRevokeFolder.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not access folder after revoke, got {(int)bobPostRevokeFolder.StatusCode}");

        var bobPostRevokeFile = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.True(
            bobPostRevokeFile.StatusCode == HttpStatusCode.Forbidden ||
            bobPostRevokeFile.StatusCode == HttpStatusCode.NotFound,
            $"Bob should not download file after revoke, got {(int)bobPostRevokeFile.StatusCode}");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 4: Session Lifecycle
    //   Authenticate → operate → session expires → 401 → re-authenticate
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SessionLifecycle_ExpiredSession_RequiresReauthentication()
    {
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // Authenticate and perform operations
        var session1 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session1);

        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);

        // Invalidate the session (simulate expiry by removing from session store)
        using (var scope = _factory.Services.CreateScope())
        {
            var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
            sessionStore.DeleteSession(session1);
        }

        // Operations now fail with 401
        var failResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, failResp.StatusCode);

        // Re-authenticate via wallet
        var session2 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);
        Assert.NotEqual(session1, session2);

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session2);

        // Operations work again
        var successResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, successResp.StatusCode);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 5: Concurrent Wallet Sessions (same DID, multiple devices)
    //   Same wallet authenticates twice → both sessions valid → revoke one
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task ConcurrentSessions_SameWalletMultipleDevices_BothSessionsWork()
    {
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // Authenticate from "device 1"
        var session1 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);

        // Authenticate from "device 2"
        var session2 = await TestFixture.AuthenticateWalletViaSseAsync(_factory, walletIdentity, credential);

        Assert.NotEqual(session1, session2);

        // Both sessions should work
        var device1Client = _factory.CreateClient();
        device1Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session1);
        var d1Resp = await device1Client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, d1Resp.StatusCode);

        var device2Client = _factory.CreateClient();
        device2Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session2);
        var d2Resp = await device2Client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, d2Resp.StatusCode);

        // Device 1 creates a folder — visible from device 2
        var folderId = await TestFixture.CreateFolderAsync(device1Client, "Cross-Device Folder");
        var d2FolderResp = await device2Client.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, d2FolderResp.StatusCode);

        // Revoke session 1
        using (var scope = _factory.Services.CreateScope())
        {
            var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();
            sessionStore.DeleteSession(session1);
        }

        // Session 1 is now invalid
        var d1FailResp = await device1Client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, d1FailResp.StatusCode);

        // Session 2 still works
        var d2StillOk = await device2Client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, d2StillOk.StatusCode);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Helper Methods
    // ═══════════════════════════════════════════════════════════════════════

    private static async Task<string> GetFileId(HttpClient client, string folderId, string fileName)
    {
        var resp = await client.GetAsync($"/api/folders/{folderId}/files");
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        for (int i = 0; i < items.GetArrayLength(); i++)
        {
            if (items[i].GetProperty("name").GetString() == fileName)
                return items[i].GetProperty("id").GetString()!;
        }
        throw new InvalidOperationException($"File '{fileName}' not found in folder {folderId}");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Factory
    // ═══════════════════════════════════════════════════════════════════════

    public class WalletDriveFactory : SsdidDriveFactory
    {
        public MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.AddHttpClient<RegistryClient>()
                    .ConfigurePrimaryHttpMessageHandler(() => MockRegistryHandler);
            });
        }
    }
}
