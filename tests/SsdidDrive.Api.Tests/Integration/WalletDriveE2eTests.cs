using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
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

    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public WalletDriveE2eTests(WalletDriveFactory factory) => _factory = factory;

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 1: New User Journey
    //   Wallet registers → SSE delivers session → first drive operations
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task NewUserJourney_WalletRegisterAndAuthenticate_CanPerformDriveOperations()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var client = _factory.CreateClient();

        // Step 1: Client initiates login (displays QR)
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        Assert.Equal(HttpStatusCode.OK, initResp.StatusCode);
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        // Step 2: Client subscribes to SSE (background)
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var sseTask = ReadSseEvent(client, challengeId, subscriberSecret, cts.Token);

        // Step 3: Wallet scans QR → registers with service
        var walletClient = _factory.CreateClient();
        var credential = await RegisterWallet(walletClient, walletIdentity);

        // Step 4: Wallet authenticates with the credential + challengeId
        var authResp = await walletClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);

        // Step 5: Client receives session token via SSE
        var sseData = await sseTask;
        Assert.NotNull(sseData);
        var sessionToken = sseData.Value.GetProperty("session_token").GetString()!;

        // Step 6: Client uses session token for drive operations
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        // 6a: Check profile
        var meResp = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);
        var meBody = await meResp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        Assert.Equal(walletIdentity.Did, meBody.GetProperty("did").GetString());

        // 6b: Create a folder
        var folderId = await CreateFolderAsync(client, "My First Folder");
        Assert.False(string.IsNullOrEmpty(folderId));

        // 6c: Upload a file
        var fileId = await UploadFileAsync(client, folderId, "hello.txt", "encrypted-content-hello");
        Assert.False(string.IsNullOrEmpty(fileId));

        // 6d: List files in folder
        var listResp = await client.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, listResp.StatusCode);
        var listBody = await listResp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        var items = listBody.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);
        Assert.Contains("hello.txt",
            Enumerable.Range(0, items.GetArrayLength())
                .Select(i => items[i].GetProperty("name").GetString()));

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
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        // Pre-register the wallet
        var regClient = _factory.CreateClient();
        var credential = await RegisterWallet(regClient, walletIdentity);

        // First login: establish presence and upload a file
        var session1 = await AuthenticateViaSse(walletIdentity, credential);
        var client1 = _factory.CreateClient();
        client1.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session1);
        var folderId = await CreateFolderAsync(client1, "Returning User Folder");
        await UploadFileAsync(client1, folderId, "doc.pdf", "encrypted-pdf-data");

        // Second login: returning user authenticates again
        var session2 = await AuthenticateViaSse(walletIdentity, credential);
        Assert.NotEqual(session1, session2); // New session each time

        var client2 = _factory.CreateClient();
        client2.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", session2);

        // Returning user can access previously uploaded data
        var meResp = await client2.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);

        var filesResp = await client2.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, filesResp.StatusCode);
        var filesBody = await filesResp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        Assert.Contains("doc.pdf",
            Enumerable.Range(0, filesBody.GetProperty("items").GetArrayLength())
                .Select(i => filesBody.GetProperty("items")[i].GetProperty("name").GetString()));

        var dlResp = await client2.GetAsync($"/api/files/{(await GetFileId(client2, folderId, "doc.pdf"))}/download");
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
        var (aliceWallet, _) = CreateWalletIdentity();
        var (bobWallet, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(aliceWallet.Did, aliceWallet.BuildDidDocument());
        _factory.MockRegistryHandler.RegisterDid(bobWallet.Did, bobWallet.BuildDidDocument());

        // Alice registers and authenticates
        var aliceRegClient = _factory.CreateClient();
        var aliceCred = await RegisterWallet(aliceRegClient, aliceWallet);
        var aliceToken = await AuthenticateViaSse(aliceWallet, aliceCred);
        var alice = _factory.CreateClient();
        alice.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", aliceToken);

        // Bob registers and authenticates
        var bobRegClient = _factory.CreateClient();
        var bobCred = await RegisterWallet(bobRegClient, bobWallet);
        var bobToken = await AuthenticateViaSse(bobWallet, bobCred);
        var bob = _factory.CreateClient();
        bob.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", bobToken);

        // Add Bob to Alice's tenant so sharing is possible (lookup via DB)
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var aliceUser = await db.Users.FirstAsync(u => u.Did == aliceWallet.Did);
            var bobUser = await db.Users.FirstAsync(u => u.Did == bobWallet.Did);
            var bobUserId = bobUser.Id;
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

        // Get Bob's user ID for sharing
        Guid bobUserId2;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            bobUserId2 = (await db.Users.FirstAsync(u => u.Did == bobWallet.Did)).Id;
        }

        // Alice creates folder, uploads file
        var folderId = await CreateFolderAsync(alice, "Alice Shared Folder");
        var fileId = await UploadFileAsync(alice, folderId, "shared-doc.bin", "alice-encrypted-payload");

        // Bob CANNOT access before sharing
        var bobPreAccess = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobPreAccess.StatusCode == HttpStatusCode.Forbidden ||
            bobPreAccess.StatusCode == HttpStatusCode.NotFound);

        // Alice shares folder with Bob (read)
        var shareResp = await alice.PostAsJsonAsync("/api/shares", new
        {
            resource_id = Guid.Parse(folderId),
            resource_type = "folder",
            shared_with_id = bobUserId2,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        }, SnakeJson);
        Assert.Equal(HttpStatusCode.Created, shareResp.StatusCode);
        var shareBody = await shareResp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
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
        var receivedBody = await receivedResp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        var receivedItems = receivedBody.GetProperty("items");
        Assert.True(receivedItems.GetArrayLength() >= 1);

        // Alice revokes the share
        var revokeResp = await alice.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // Bob can NO LONGER access
        var bobPostRevoke = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            bobPostRevoke.StatusCode == HttpStatusCode.Forbidden ||
            bobPostRevoke.StatusCode == HttpStatusCode.NotFound);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Scenario 4: Session Lifecycle
    //   Authenticate → operate → session expires → 401 → re-authenticate
    // ═══════════════════════════════════════════════════════════════════════

    [Fact]
    public async Task SessionLifecycle_ExpiredSession_RequiresReauthentication()
    {
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var regClient = _factory.CreateClient();
        var credential = await RegisterWallet(regClient, walletIdentity);

        // Authenticate and perform operations
        var session1 = await AuthenticateViaSse(walletIdentity, credential);
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
        var session2 = await AuthenticateViaSse(walletIdentity, credential);
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
        var (walletIdentity, _) = CreateWalletIdentity();
        _factory.MockRegistryHandler.RegisterDid(walletIdentity.Did, walletIdentity.BuildDidDocument());

        var regClient = _factory.CreateClient();
        var credential = await RegisterWallet(regClient, walletIdentity);

        // Authenticate from "device 1"
        var session1 = await AuthenticateViaSse(walletIdentity, credential);

        // Authenticate from "device 2"
        var session2 = await AuthenticateViaSse(walletIdentity, credential);

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
        var folderId = await CreateFolderAsync(device1Client, "Cross-Device Folder");
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

    private (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateWalletIdentity()
    {
        var providers = new ICryptoProvider[] { new Ed25519Provider() };
        var cryptoFactory = new CryptoProviderFactory(providers);
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        return (identity, cryptoFactory);
    }

    private async Task<JsonElement> RegisterWallet(HttpClient client, SsdidIdentity walletIdentity)
    {
        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId }, SnakeJson);
        regResp.EnsureSuccessStatusCode();
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        var signedChallenge = walletIdentity.SignChallenge(challenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId, signed_challenge = signedChallenge },
            SnakeJson);
        verifyResp.EnsureSuccessStatusCode();
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        return verifyBody.GetProperty("credential");
    }

    /// <summary>
    /// Full SSE-based authentication flow: initiate → subscribe SSE → wallet authenticates → receive token.
    /// </summary>
    private async Task<string> AuthenticateViaSse(SsdidIdentity walletIdentity, JsonElement credential)
    {
        var client = _factory.CreateClient();

        // Initiate login
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        initResp.EnsureSuccessStatusCode();
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        // Subscribe to SSE (background)
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var sseTask = ReadSseEvent(client, challengeId, subscriberSecret, cts.Token);

        // Wallet authenticates
        var walletClient = _factory.CreateClient();
        var authResp = await walletClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, SnakeJson);
        authResp.EnsureSuccessStatusCode();

        // Receive session token via SSE
        var sseData = await sseTask;
        Assert.NotNull(sseData);
        return sseData.Value.GetProperty("session_token").GetString()!;
    }

    private async Task<JsonElement?> ReadSseEvent(HttpClient client, string challengeId, string subscriberSecret, CancellationToken ct)
    {
        var request = new HttpRequestMessage(HttpMethod.Get,
            $"/api/auth/ssdid/events?challenge_id={challengeId}&subscriber_secret={Uri.EscapeDataString(subscriberSecret)}");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/event-stream"));

        var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        while (!ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct);
            if (line is null) break;
            if (line.StartsWith("data: "))
            {
                var json = line["data: ".Length..];
                return JsonSerializer.Deserialize<JsonElement>(json);
            }
        }
        return null;
    }

    private static async Task<string> CreateFolderAsync(HttpClient client, string name)
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name,
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        }, SnakeJson);
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        return body.GetProperty("id").GetString()!;
    }

    private static async Task<string> UploadFileAsync(HttpClient client, string folderId,
        string fileName, string content)
    {
        var encKey = Convert.ToBase64String(Encoding.UTF8.GetBytes("test-file-key-0123456789abcdef"));
        var nonce = Convert.ToBase64String(new byte[12]);

        var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(Encoding.UTF8.GetBytes(content)), "file", fileName);
        form.Add(new StringContent(encKey), "encrypted_file_key");
        form.Add(new StringContent(nonce), "nonce");
        form.Add(new StringContent("AES-256-GCM"), "encryption_algorithm");

        var response = await client.PostAsync($"/api/folders/{folderId}/files", form);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(SnakeJson);
        return body.GetProperty("id").GetString()!;
    }

    private static async Task<string> GetFileId(HttpClient client, string folderId, string fileName)
    {
        var resp = await client.GetAsync($"/api/folders/{folderId}/files");
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        });
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
