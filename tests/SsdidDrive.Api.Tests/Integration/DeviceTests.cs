using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class DeviceTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public DeviceTests(SsdidDriveFactory factory) => _factory = factory;

    private static object MakeEnrollRequest(
        string fingerprint = "fp-abc123",
        string platform = "android",
        string? deviceName = "Pixel 8",
        string? deviceInfo = null,
        string keyAlgorithm = "kaz_sign",
        string? publicKey = null)
    {
        return new
        {
            device_fingerprint = fingerprint,
            platform,
            device_name = deviceName,
            device_info = deviceInfo ?? """{"model":"Pixel 8","os":"Android 15"}""",
            key_algorithm = keyAlgorithm,
            public_key = publicKey ?? Convert.ToBase64String(new byte[32])
        };
    }

    // ── 1. Enroll device → 201 ─────────────────────────────────────────

    [Fact]
    public async Task EnrollDevice_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceEnroll");

        var fingerprint = $"fp-{Guid.NewGuid():N}";
        var response = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(fingerprint, body.GetProperty("device_fingerprint").GetString());
        Assert.Equal("android", body.GetProperty("platform").GetString());
        Assert.Equal("Pixel 8", body.GetProperty("device_name").GetString());
        Assert.Equal("kaz_sign", body.GetProperty("key_algorithm").GetString());
        Assert.Equal(userId, body.GetProperty("user_id").GetGuid());
    }

    // ── 2. Enroll duplicate fingerprint → 409 ──────────────────────────

    [Fact]
    public async Task EnrollDevice_DuplicateFingerprint_ReturnsConflict()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceDup");

        var fingerprint = $"fp-dup-{Guid.NewGuid():N}";
        var resp1 = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, resp1.StatusCode);

        var resp2 = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, resp2.StatusCode);
    }

    // ── 3. Enroll with missing platform → 400 ──────────────────────────

    [Fact]
    public async Task EnrollDevice_MissingPlatform_ReturnsBadRequest()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceMissingPlatform");

        var request = new
        {
            device_fingerprint = $"fp-{Guid.NewGuid():N}",
            platform = "",
            key_algorithm = "kaz_sign",
            public_key = Convert.ToBase64String(new byte[32])
        };

        var response = await client.PostAsJsonAsync("/api/devices", request, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 4. List devices → 200 ──────────────────────────────────────────

    [Fact]
    public async Task ListDevices_ReturnsEnrolledDevices()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceList");

        var fp1 = $"fp-list1-{Guid.NewGuid():N}";
        var fp2 = $"fp-list2-{Guid.NewGuid():N}";
        await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fp1, deviceName: "Device 1"), TestFixture.Json);
        await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fp2, deviceName: "Device 2"), TestFixture.Json);

        var response = await client.GetAsync("/api/devices");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var devices = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(devices.GetArrayLength() >= 2);

        var fingerprints = Enumerable.Range(0, devices.GetArrayLength())
            .Select(i => devices[i].GetProperty("device_fingerprint").GetString())
            .ToList();
        Assert.Contains(fp1, fingerprints);
        Assert.Contains(fp2, fingerprints);
    }

    // ── 5. Get current device by fingerprint → 200 ─────────────────────

    [Fact]
    public async Task GetCurrentDevice_ReturnsDevice()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceCurrent");

        var fingerprint = $"fp-current-{Guid.NewGuid():N}";
        await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);

        var response = await client.GetAsync($"/api/devices/current?fingerprint={fingerprint}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(fingerprint, body.GetProperty("device_fingerprint").GetString());
    }

    // ── 6. Get current device with missing fingerprint → 404 ───────────

    [Fact]
    public async Task GetCurrentDevice_MissingFingerprint_ReturnsNotFound()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceNoFP");

        var response = await client.GetAsync("/api/devices/current?fingerprint=nonexistent-fp");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 7. Update device name → 200 ────────────────────────────────────

    [Fact]
    public async Task UpdateDevice_ReturnsOk()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceUpdate");

        var fingerprint = $"fp-update-{Guid.NewGuid():N}";
        var enrollResp = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        var enrollBody = await enrollResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var deviceId = enrollBody.GetProperty("id").GetString();

        var updateReq = new { device_name = "My Updated Phone" };
        var response = await client.PatchAsJsonAsync($"/api/devices/{deviceId}", updateReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("My Updated Phone", body.GetProperty("device_name").GetString());
    }

    // ── 8. Update device as non-owner → 403 ────────────────────────────

    [Fact]
    public async Task UpdateDevice_NonOwner_ReturnsForbidden()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "DeviceNonOwner");

        var fingerprint = $"fp-nonowner-{Guid.NewGuid():N}";
        var enrollResp = await client1.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        var enrollBody = await enrollResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var deviceId = enrollBody.GetProperty("id").GetString();

        var updateReq = new { device_name = "Hacked Name" };
        var response = await client2.PatchAsJsonAsync($"/api/devices/{deviceId}", updateReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ── 9. Revoke device → 204 ─────────────────────────────────────────

    [Fact]
    public async Task RevokeDevice_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceRevoke");

        var fingerprint = $"fp-revoke-{Guid.NewGuid():N}";
        var enrollResp = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        var enrollBody = await enrollResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var deviceId = enrollBody.GetProperty("id").GetString();

        var response = await client.DeleteAsync($"/api/devices/{deviceId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    // ── 10. Revoke sets status to Revoked ──────────────────────────────

    [Fact]
    public async Task RevokeDevice_SetsStatusToRevoked()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeviceRevokeVerify");

        var fingerprint = $"fp-revokev-{Guid.NewGuid():N}";
        var enrollResp = await client.PostAsJsonAsync("/api/devices", MakeEnrollRequest(fingerprint: fingerprint), TestFixture.Json);
        var enrollBody = await enrollResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var deviceId = enrollBody.GetProperty("id").GetString();

        await client.DeleteAsync($"/api/devices/{deviceId}");

        // Verify status via list (revoked devices still appear)
        var listResp = await client.GetAsync("/api/devices");
        var devices = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);

        var revokedDevice = Enumerable.Range(0, devices.GetArrayLength())
            .Select(i => devices[i])
            .FirstOrDefault(d => d.GetProperty("id").GetString() == deviceId);

        Assert.Equal("Revoked", revokedDevice.GetProperty("status").GetString());
    }
}
