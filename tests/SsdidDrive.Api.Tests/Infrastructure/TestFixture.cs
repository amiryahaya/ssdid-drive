using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.Crypto.Providers;
using Ssdid.Sdk.Server.Identity;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Tests.Infrastructure;

public static class TestFixture
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public static JsonSerializerOptions Json => JsonOptions;

    public static async Task<(HttpClient Client, Guid UserId, Guid TenantId)> CreateAuthenticatedClientAsync(
        SsdidDriveFactory factory,
        string? displayName = null,
        string? did = null,
        string? systemRole = null)
    {
        did ??= $"did:ssdid:test-{Guid.NewGuid():N}";

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();

        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = "Test Tenant",
            Slug = $"test-{Guid.NewGuid():N}"[..32],
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);
        await db.SaveChangesAsync();

        var user = new User
        {
            Id = Guid.NewGuid(),
            Did = did,
            DisplayName = displayName ?? "Test User",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        if (systemRole is not null)
            user.SystemRole = Enum.Parse<SystemRole>(systemRole);

        db.Users.Add(user);

        var userTenant = new UserTenant
        {
            UserId = user.Id,
            TenantId = tenant.Id,
            Role = TenantRole.Owner,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.UserTenants.Add(userTenant);
        await db.SaveChangesAsync();

        var sessionToken = CreateTestSession(sessionStore, did);

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id, tenant.Id);
    }

    public static async Task<(HttpClient Client, Guid UserId)> CreateUserInTenantAsync(
        SsdidDriveFactory factory, Guid tenantId, string displayName = "Tenant Member")
    {
        var did = $"did:ssdid:test-{Guid.NewGuid():N}";

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<ISessionStore>();

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

        var sessionToken = CreateTestSession(sessionStore, did);

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id);
    }

    public static async Task<string> CreateFolderAsync(HttpClient client, string name = "Test Folder")
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name,
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        }, Json);
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(Json);
        return body.GetProperty("data").GetProperty("id").GetString()!;
    }

    public static async Task<string> UploadFileAsync(HttpClient client, string folderId,
        string fileName = "test.bin", string content = "encrypted-data")
    {
        var encKey = Convert.ToBase64String(Encoding.UTF8.GetBytes("test-file-key-0123456789abcdef"));
        var nonce = Convert.ToBase64String(new byte[12]);

        var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(Encoding.UTF8.GetBytes(content)), "file", fileName);
        form.Add(new StringContent(encKey), "encrypted_file_key");
        form.Add(new StringContent(nonce), "nonce");
        form.Add(new StringContent("AES-256-GCM"), "encryption_algorithm");

        var url = $"/api/folders/{folderId}/files";

        var response = await client.PostAsync(url, form);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return body.GetProperty("id").GetString()!;
    }

    public static async Task<(HttpStatusCode Status, JsonElement Body)> CreateShareAsync(
        HttpClient client, string resourceId, Guid sharedWithId,
        string permission = "read", string resourceType = "folder")
    {
        var request = new
        {
            resource_id = Guid.Parse(resourceId),
            resource_type = resourceType,
            shared_with_id = sharedWithId,
            permission,
            encrypted_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "ML-KEM-768"
        };

        var response = await client.PostAsJsonAsync("/api/shares", request, Json);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return (response.StatusCode, body);
    }

    // ── Wallet Identity Helpers ──

    public static (SsdidIdentity Identity, CryptoProviderFactory CryptoFactory) CreateWalletIdentity()
    {
        var providers = new ICryptoProvider[] { new Ed25519Provider() };
        var cryptoFactory = new CryptoProviderFactory(providers);
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        return (identity, cryptoFactory);
    }

    public static async Task<JsonElement> RegisterWalletAsync(
        SsdidDriveFactory factory, SsdidIdentity walletIdentity)
    {
        var client = factory.CreateClient();

        var regResp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId }, Json);
        regResp.EnsureSuccessStatusCode();
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        var signedChallenge = walletIdentity.SignChallenge(challenge);
        var verifyResp = await client.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = walletIdentity.Did, key_id = walletIdentity.KeyId, signed_challenge = signedChallenge },
            Json);
        verifyResp.EnsureSuccessStatusCode();
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        return verifyBody.GetProperty("credential");
    }

    private static readonly TimeSpan SseTimeout = TimeSpan.FromSeconds(10);

    /// <summary>
    /// Reads the first SSE data event, or throws <see cref="TimeoutException"/> with a diagnostic message.
    /// </summary>
    public static async Task<JsonElement> ReadSseEventOrFail(
        HttpClient client, string challengeId, string subscriberSecret,
        CancellationToken ct, string context = "")
    {
        var request = new HttpRequestMessage(HttpMethod.Get,
            $"/api/auth/ssdid/events?challenge_id={challengeId}&subscriber_secret={Uri.EscapeDataString(subscriberSecret)}");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/event-stream"));

        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
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

        throw new TimeoutException(
            $"SSE event not received within timeout{(context.Length > 0 ? $" ({context})" : "")}");
    }

    /// <summary>
    /// Full SSE-based wallet authentication: initiate → subscribe SSE → wallet authenticates → returns session token.
    /// </summary>
    public static async Task<string> AuthenticateWalletViaSseAsync(
        SsdidDriveFactory factory, SsdidIdentity walletIdentity, JsonElement credential)
    {
        var client = factory.CreateClient();

        // Initiate login
        var initResp = await client.PostAsync("/api/auth/ssdid/login/initiate", null);
        initResp.EnsureSuccessStatusCode();
        var initBody = await initResp.Content.ReadFromJsonAsync<JsonElement>();
        var challengeId = initBody.GetProperty("challenge_id").GetString()!;
        var subscriberSecret = initBody.GetProperty("subscriber_secret").GetString()!;

        // Subscribe to SSE (background) — use a separate client to avoid header mutation
        var sseClient = factory.CreateClient();
        using var cts = new CancellationTokenSource(SseTimeout);
        var sseTask = ReadSseEventOrFail(sseClient, challengeId, subscriberSecret, cts.Token, "wallet auth SSE");

        // Wallet authenticates
        var walletClient = factory.CreateClient();
        var authResp = await walletClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential, challenge_id = challengeId }, Json);
        authResp.EnsureSuccessStatusCode();

        // Receive session token via SSE
        var sseData = await sseTask;
        return sseData.GetProperty("session_token").GetString()!;
    }

    /// <summary>
    /// Creates a session via the public ISessionStore API and returns the generated token.
    /// </summary>
    private static string CreateTestSession(ISessionStore store, string did)
    {
        var token = store.CreateSession(did);
        return token ?? throw new InvalidOperationException("Session store returned null — session limit reached in test setup");
    }
}
