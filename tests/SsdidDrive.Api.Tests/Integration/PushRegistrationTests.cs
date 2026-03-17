using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class PushRegistrationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public PushRegistrationTests(SsdidDriveFactory factory) => _factory = factory;

    private async Task<(HttpClient Client, Guid DeviceId)> EnrollDeviceAsync(
        HttpClient client, string? fingerprint = null)
    {
        fingerprint ??= $"fp-push-{Guid.NewGuid():N}";
        var request = new
        {
            device_fingerprint = fingerprint,
            platform = "android",
            device_name = "Test Device",
            device_info = """{"model":"Pixel 8","os":"Android 15"}""",
            key_algorithm = "kaz_sign",
            public_key = Convert.ToBase64String(new byte[32])
        };

        var response = await client.PostAsJsonAsync("/api/devices", request, TestFixture.Json);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var deviceId = body.GetProperty("id").GetGuid();
        return (client, deviceId);
    }

    // ── 1. RegisterPush sets player_id → 204 ────────────────────────────

    [Fact]
    public async Task RegisterPush_SetsPlayerId_Returns204()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PushRegister");
        var (_, deviceId) = await EnrollDeviceAsync(client);

        var response = await client.PostAsJsonAsync(
            $"/api/devices/{deviceId}/push",
            new { player_id = "onesignal-player-123" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify via DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var device = await db.Devices.FindAsync(deviceId);
        Assert.NotNull(device);
        Assert.Equal("onesignal-player-123", device!.PushPlayerId);
    }

    // ── 2. RegisterPush with empty player_id → 400 ──────────────────────

    [Fact]
    public async Task RegisterPush_EmptyPlayerId_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PushEmpty");
        var (_, deviceId) = await EnrollDeviceAsync(client);

        var response = await client.PostAsJsonAsync(
            $"/api/devices/{deviceId}/push",
            new { player_id = "" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 3. RegisterPush on device owned by another user → 404 ───────────

    [Fact]
    public async Task RegisterPush_DeviceOwnedByOtherUser_Returns404()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PushOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PushOther");

        var (_, deviceId) = await EnrollDeviceAsync(client1);

        // Other user tries to register push on device they don't own
        var response = await client2.PostAsJsonAsync(
            $"/api/devices/{deviceId}/push",
            new { player_id = "onesignal-player-456" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 4. UnregisterPush clears player_id → 204 ────────────────────────

    [Fact]
    public async Task UnregisterPush_ClearsPlayerId_Returns204()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PushUnregister");
        var (_, deviceId) = await EnrollDeviceAsync(client);

        // First register push
        await client.PostAsJsonAsync(
            $"/api/devices/{deviceId}/push",
            new { player_id = "onesignal-player-789" },
            TestFixture.Json);

        // Then unregister
        var response = await client.DeleteAsync($"/api/devices/{deviceId}/push");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify via DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var device = await db.Devices.FindAsync(deviceId);
        Assert.NotNull(device);
        Assert.Null(device!.PushPlayerId);
    }

    // ── 5. UnregisterPush on device not owned → 404 ─────────────────────

    [Fact]
    public async Task UnregisterPush_NotOwner_Returns404()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PushUnregOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PushUnregOther");

        var (_, deviceId) = await EnrollDeviceAsync(client1);

        // Register push first
        await client1.PostAsJsonAsync(
            $"/api/devices/{deviceId}/push",
            new { player_id = "onesignal-player-abc" },
            TestFixture.Json);

        // Other user tries to unregister
        var response = await client2.DeleteAsync($"/api/devices/{deviceId}/push");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
