using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class RecoveryTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public RecoveryTests(SsdidDriveFactory factory) => _factory = factory;

    // ── 1. SetupRecovery_ReturnsCreated ────────────────────────────────

    [Fact]
    public async Task SetupRecovery_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoverySetup");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold = 3,
            total_shares = 5
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, body.GetProperty("threshold").GetInt32());
        Assert.Equal(5, body.GetProperty("total_shares").GetInt32());
        Assert.True(body.GetProperty("is_active").GetBoolean());
    }

    // ── 2. SetupRecovery_InvalidThreshold_Returns400 ──────────────────

    [Fact]
    public async Task SetupRecovery_InvalidThreshold_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryBadThreshold");

        // threshold < 2
        var response1 = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold = 1,
            total_shares = 5
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response1.StatusCode);

        // threshold > total_shares
        var response2 = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold = 6,
            total_shares = 5
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response2.StatusCode);

        // total_shares > 10
        var response3 = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold = 3,
            total_shares = 11
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.BadRequest, response3.StatusCode);
    }

    // ── 3. DistributeShare_ReturnsCreated ─────────────────────────────

    [Fact]
    public async Task DistributeShare_ReturnsCreated()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryDistOwner");
        var (_, trusteeId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RecoveryTrustee");

        var configId = await SetupRecoveryAsync(client);

        var response = await client.PostAsJsonAsync("/api/recovery/shares", new
        {
            recovery_config_id = configId,
            trustee_id = trusteeId,
            encrypted_share = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(trusteeId, body.GetProperty("trustee_id").GetGuid());
        Assert.Equal("Pending", body.GetProperty("status").GetString());
    }

    // ── 4. ListTrusteeShares_ReturnsShares ────────────────────────────

    [Fact]
    public async Task ListTrusteeShares_ReturnsShares()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryListOwner");
        var (trusteeClient, trusteeId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RecoveryListTrustee");

        var configId = await SetupRecoveryAsync(ownerClient);
        await DistributeShareAsync(ownerClient, configId, trusteeId);

        var response = await trusteeClient.GetAsync("/api/recovery/shares");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);
    }

    // ── 5. AcceptShare_ReturnsOk ──────────────────────────────────────

    [Fact]
    public async Task AcceptShare_ReturnsOk()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryAcceptOwner");
        var (trusteeClient, trusteeId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RecoveryAcceptTrustee");

        var configId = await SetupRecoveryAsync(ownerClient);
        var shareId = await DistributeShareAsync(ownerClient, configId, trusteeId);

        var response = await trusteeClient.PostAsync($"/api/recovery/shares/{shareId}/accept", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Accepted", body.GetProperty("status").GetString());
    }

    // ── 6. RejectShare_ReturnsOk ──────────────────────────────────────

    [Fact]
    public async Task RejectShare_ReturnsOk()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryRejectOwner");
        var (trusteeClient, trusteeId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RecoveryRejectTrustee");

        var configId = await SetupRecoveryAsync(ownerClient);
        var shareId = await DistributeShareAsync(ownerClient, configId, trusteeId);

        var response = await trusteeClient.PostAsync($"/api/recovery/shares/{shareId}/reject", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Rejected", body.GetProperty("status").GetString());
    }

    // ── 7. InitiateRecovery_ReturnsCreated ────────────────────────────

    [Fact]
    public async Task InitiateRecovery_ReturnsCreated()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryInitiateUser");

        var configId = await SetupRecoveryAsync(client);

        var response = await client.PostAsJsonAsync("/api/recovery/requests", new
        {
            recovery_config_id = configId
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Pending", body.GetProperty("status").GetString());
        Assert.Equal(0, body.GetProperty("approvals_received").GetInt32());
    }

    // ── 8. ApproveRecovery_IncrementsApprovals ────────────────────────

    [Fact]
    public async Task ApproveRecovery_IncrementsApprovals()
    {
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryApproveOwner");
        var (trustee1Client, trustee1Id) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ApprovalTrustee1");
        var (trustee2Client, trustee2Id) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "ApprovalTrustee2");

        // Setup with threshold=2, total=3
        var setupResp = await ownerClient.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold = 2,
            total_shares = 3
        }, TestFixture.Json);
        var setupBody = await setupResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var configId = setupBody.GetProperty("id").GetGuid();

        // Distribute shares to both trustees
        var share1Id = await DistributeShareAsync(ownerClient, configId, trustee1Id);
        var share2Id = await DistributeShareAsync(ownerClient, configId, trustee2Id);

        // Trustees accept their shares
        await trustee1Client.PostAsync($"/api/recovery/shares/{share1Id}/accept", null);
        await trustee2Client.PostAsync($"/api/recovery/shares/{share2Id}/accept", null);

        // Initiate recovery
        var initiateResp = await ownerClient.PostAsJsonAsync("/api/recovery/requests", new
        {
            recovery_config_id = configId
        }, TestFixture.Json);
        var initiateBody = await initiateResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var requestId = initiateBody.GetProperty("id").GetGuid();

        // First trustee approves
        var approve1 = await trustee1Client.PostAsJsonAsync($"/api/recovery/requests/{requestId}/approve", new
        {
            encrypted_share = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, approve1.StatusCode);
        var approve1Body = await approve1.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(1, approve1Body.GetProperty("approvals_received").GetInt32());
        Assert.Equal("Pending", approve1Body.GetProperty("status").GetString());

        // Second trustee approves — should reach threshold
        var approve2 = await trustee2Client.PostAsJsonAsync($"/api/recovery/requests/{requestId}/approve", new
        {
            encrypted_share = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, approve2.StatusCode);
        var approve2Body = await approve2.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(2, approve2Body.GetProperty("approvals_received").GetInt32());
        Assert.Equal("Approved", approve2Body.GetProperty("status").GetString());
    }

    // ── 9. GetRecoveryStatus_ReturnsConfig ────────────────────────────

    [Fact]
    public async Task GetRecoveryStatus_ReturnsConfig()
    {
        var (client, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryStatusUser");
        var (_, trusteeId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "RecoveryStatusTrustee");

        var configId = await SetupRecoveryAsync(client);
        await DistributeShareAsync(client, configId, trusteeId);

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, body.GetProperty("threshold").GetInt32());
        Assert.Equal(5, body.GetProperty("total_shares").GetInt32());
        Assert.True(body.GetProperty("is_active").GetBoolean());
        Assert.True(body.GetProperty("shares").GetArrayLength() >= 1);
    }

    // ── 10. GetRecoveryStatus_NoConfig_Returns404 ─────────────────────

    [Fact]
    public async Task GetRecoveryStatus_NoConfig_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryNo404User");

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 11. GetRecoveryRequest_ReturnsStatus ──────────────────────────

    [Fact]
    public async Task GetRecoveryRequest_ReturnsStatus()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryGetReqUser");

        var configId = await SetupRecoveryAsync(client);

        var initiateResp = await client.PostAsJsonAsync("/api/recovery/requests", new
        {
            recovery_config_id = configId
        }, TestFixture.Json);
        var initiateBody = await initiateResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var requestId = initiateBody.GetProperty("id").GetGuid();

        var response = await client.GetAsync($"/api/recovery/requests/{requestId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Pending", body.GetProperty("status").GetString());
        Assert.Equal(0, body.GetProperty("approvals_received").GetInt32());
    }

    // ── Helpers ───────────────────────────────────────────────────────

    private static async Task<Guid> SetupRecoveryAsync(HttpClient client, int threshold = 3, int totalShares = 5)
    {
        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            threshold,
            total_shares = totalShares
        }, TestFixture.Json);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetGuid();
    }

    private static async Task<Guid> DistributeShareAsync(HttpClient client, Guid configId, Guid trusteeId)
    {
        var response = await client.PostAsJsonAsync("/api/recovery/shares", new
        {
            recovery_config_id = configId,
            trustee_id = trusteeId,
            encrypted_share = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetGuid();
    }
}
