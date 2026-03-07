using System.Net.Http.Headers;
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

    public static async Task<(HttpClient Client, Guid UserId, Guid TenantId)> CreateAuthenticatedClientAsync(
        SsdidDriveFactory factory,
        string? displayName = null,
        string? did = null)
    {
        did ??= $"did:ssdid:test-{Guid.NewGuid():N}";
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<SessionStore>();

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

    public static JsonSerializerOptions Json => JsonOptions;
}
