using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ExtensionServiceTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public ExtensionServiceTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RegisterService_ValidRequest_ReturnsCreatedWithSecret()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Test Analytics",
            permissions = new { files_read = true, activity_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.True(body.TryGetProperty("id", out _));
        Assert.True(body.TryGetProperty("service_key", out var keyProp));
        Assert.False(string.IsNullOrEmpty(keyProp.GetString()));
        Assert.Equal("Test Analytics", body.GetProperty("name").GetString());
    }

    [Fact]
    public async Task RegisterService_DuplicateName_ReturnsConflict()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Unique Service",
            permissions = new { files_read = true }
        }, Json);

        var response = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Unique Service",
            permissions = new { files_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task RegisterService_MemberRole_ReturnsForbidden()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId);

        var response = await memberClient.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Member Service",
            permissions = new { files_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ListServices_ReturnsAllServicesForTenant()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await client.PostAsJsonAsync("/api/tenant/services", new { name = "List Svc A", permissions = new { files_read = true } }, Json);
        await client.PostAsJsonAsync("/api/tenant/services", new { name = "List Svc B", permissions = new { activity_read = true } }, Json);

        var response = await client.GetAsync("/api/tenant/services");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 2);

        // Secret should NOT be returned in list
        var first = items[0];
        Assert.False(first.TryGetProperty("service_key", out _));
    }

    [Fact]
    public async Task GetService_ValidId_ReturnsServiceDetails()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Details Svc", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await client.GetAsync($"/api/tenant/services/{serviceId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Equal("Details Svc", body.GetProperty("name").GetString());
        Assert.False(body.TryGetProperty("service_key", out _));
    }

    [Fact]
    public async Task GetService_WrongTenant_ReturnsNotFound()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client1.PostAsJsonAsync("/api/tenant/services", new { name = "Isolated Svc", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await client2.GetAsync($"/api/tenant/services/{serviceId}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task UpdateService_ValidRequest_UpdatesPermissionsAndEnabled()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Updatable", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await client.PutAsJsonAsync($"/api/tenant/services/{serviceId}", new
        {
            permissions = new { files_read = true, files_write = true, activity_read = true },
            enabled = false
        }, Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.False(body.GetProperty("enabled").GetBoolean());
    }

    [Fact]
    public async Task RevokeService_ValidId_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Revokable", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await client.DeleteAsync($"/api/tenant/services/{serviceId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var getResponse = await client.GetAsync($"/api/tenant/services/{serviceId}");
        Assert.Equal(HttpStatusCode.NotFound, getResponse.StatusCode);
    }

    [Fact]
    public async Task RotateSecret_ValidId_ReturnsNewSecret()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Rotatable", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();
        var originalKey = createBody.GetProperty("service_key").GetString();

        var response = await client.PostAsync($"/api/tenant/services/{serviceId}/rotate", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var newKey = body.GetProperty("service_key").GetString();
        Assert.NotEqual(originalKey, newKey);
        Assert.False(string.IsNullOrEmpty(newKey));
    }

    [Fact]
    public async Task UpdateService_MemberRole_ReturnsForbidden()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId);

        var createResp = await ownerClient.PostAsJsonAsync("/api/tenant/services", new { name = "Update Auth Test", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await memberClient.PutAsJsonAsync($"/api/tenant/services/{serviceId}", new
        {
            permissions = new { files_read = true, files_write = true },
            enabled = false
        }, Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RevokeService_MemberRole_ReturnsForbidden()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId);

        var createResp = await ownerClient.PostAsJsonAsync("/api/tenant/services", new { name = "Revoke Auth Test", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await memberClient.DeleteAsync($"/api/tenant/services/{serviceId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RotateSecret_MemberRole_ReturnsForbidden()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId);

        var createResp = await ownerClient.PostAsJsonAsync("/api/tenant/services", new { name = "Rotate Auth Test", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();

        var response = await memberClient.PostAsync($"/api/tenant/services/{serviceId}/rotate", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RotatedKey_InvalidatesOldSignatures()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Sig Rotate Test", permissions = new { files_read = true } }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceId = createBody.GetProperty("id").GetString();
        var oldKey = createBody.GetProperty("service_key").GetString()!;

        var rotateResp = await client.PostAsync($"/api/tenant/services/{serviceId}/rotate", null);
        var rotateBody = await rotateResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var newKey = rotateBody.GetProperty("service_key").GetString()!;

        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var oldSig = HmacSignatureHelper.ComputeSignature(Convert.FromBase64String(oldKey), timestamp, "GET", "/test", bodyHash);
        var newSig = HmacSignatureHelper.ComputeSignature(Convert.FromBase64String(newKey), timestamp, "GET", "/test", bodyHash);

        Assert.NotEqual(oldSig, newSig);
        Assert.True(HmacSignatureHelper.VerifySignature(Convert.FromBase64String(newKey), timestamp, "GET", "/test", bodyHash, newSig));
        Assert.False(HmacSignatureHelper.VerifySignature(Convert.FromBase64String(oldKey), timestamp, "GET", "/test", bodyHash, newSig));
    }
}
