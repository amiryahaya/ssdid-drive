using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Ssdid;

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
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = (SessionStore)scope.ServiceProvider.GetRequiredService<ISessionStore>();

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

        sessionStore.CreateSessionDirect(did, sessionToken);

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id, tenant.Id);
    }

    public static async Task<(HttpClient Client, Guid UserId)> CreateUserInTenantAsync(
        SsdidDriveFactory factory, Guid tenantId, string displayName = "Tenant Member")
    {
        var did = $"did:ssdid:test-{Guid.NewGuid():N}";
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = (SessionStore)scope.ServiceProvider.GetRequiredService<ISessionStore>();

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
        return body.GetProperty("id").GetString()!;
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
}
