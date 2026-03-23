using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests for the 9 trustee-recovery endpoints:
///   POST   /api/recovery/trustees/setup
///   GET    /api/recovery/trustees
///   POST   /api/recovery/requests           (public)
///   GET    /api/recovery/requests/pending
///   POST   /api/recovery/requests/{id}/approve
///   POST   /api/recovery/requests/{id}/reject
///   GET    /api/recovery/requests/{id}/shares (public)
///   POST   /api/recovery/requests/initiate
///   GET    /api/recovery/requests/mine
/// </summary>
public class TrusteeRecoveryTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public TrusteeRecoveryTests(SsdidDriveFactory factory) => _factory = factory;

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Creates an owner user with an active recovery setup, plus 3 trustee users in the same tenant.
    /// Returns the owner client, 3 trustee clients, setup shares, and the owner DID.
    /// </summary>
    private async Task<(
        HttpClient OwnerClient,
        Guid OwnerId,
        string OwnerDid,
        Guid TenantId,
        (HttpClient Client, Guid UserId)[] Trustees)>
        CreateOwnerWithTrusteesAsync(string prefix)
    {
        var ownerDid = $"did:ssdid:trustee-owner-{prefix}-{Guid.NewGuid():N}";
        var (ownerClient, ownerId, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, $"{prefix}Owner", did: ownerDid);

        // Activate recovery setup for the owner (prerequisite for /trustees/setup)
        var setupResp = await ownerClient.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('t', 64)
        }, TestFixture.Json);
        setupResp.EnsureSuccessStatusCode();

        // Create 3 trustees in the same tenant
        var trustee1 = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, $"{prefix}Trustee1");
        var trustee2 = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, $"{prefix}Trustee2");
        var trustee3 = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, $"{prefix}Trustee3");

        return (ownerClient, ownerId, ownerDid, tenantId,
            new[] { trustee1, trustee2, trustee3 });
    }

    private static object[] BuildShares(params Guid[] trusteeIds) =>
        trusteeIds.Select((id, i) => new
        {
            trustee_user_id = id,
            encrypted_share = Convert.ToBase64String(new byte[32]),
            share_index = i + 1
        }).Cast<object>().ToArray();

    /// <summary>
    /// Performs the full trustee setup: owner calls /trustees/setup with 3 trustees, threshold 2.
    /// </summary>
    private async Task SetupTrusteesAsync(
        HttpClient ownerClient,
        (HttpClient Client, Guid UserId)[] trustees,
        int threshold = 2)
    {
        var shares = BuildShares(trustees.Select(t => t.UserId).ToArray());
        var resp = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold,
            shares
        }, TestFixture.Json);
        resp.EnsureSuccessStatusCode();
    }

    /// <summary>
    /// Creates a pending recovery request (unauthenticated) for <paramref name="did"/>.
    /// Returns the request_id.
    /// </summary>
    private async Task<Guid> CreateRecoveryRequestAsync(string did)
    {
        var client = _factory.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/recovery/requests", new { did }, TestFixture.Json);
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("request_id").GetGuid();
    }

    // ── POST /api/recovery/trustees/setup ─────────────────────────────────────

    [Fact]
    public async Task SetupTrustees_ValidRequest_ReturnsOk()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SetupValid");

        var shares = BuildShares(trustees.Select(t => t.UserId).ToArray());
        var response = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 2,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, body.GetProperty("trustee_count").GetInt32());
        Assert.Equal(2, body.GetProperty("threshold").GetInt32());
    }

    [Fact]
    public async Task SetupTrustees_ThresholdTooLow_Returns400()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SetupThresholdLow");

        var shares = BuildShares(trustees.Select(t => t.UserId).ToArray());
        var response = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 1,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupTrustees_ThresholdExceedsShares_Returns400()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SetupThresholdExceeds");

        // Only 2 shares but threshold=3
        var shares = BuildShares(trustees[0].UserId, trustees[1].UserId);
        var response = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 3,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupTrustees_SelfAsTrustee_Returns400()
    {
        var (ownerClient, ownerId, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SetupSelf");

        // Include the owner's own ID as one of the trustees
        var shares = BuildShares(ownerId, trustees[0].UserId, trustees[1].UserId);
        var response = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 2,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupTrustees_NonTenantMember_Returns400()
    {
        var (ownerClient, _, _, _, _) =
            await CreateOwnerWithTrusteesAsync("SetupNonMember");

        // Create a user in a completely different tenant
        var (_, outsiderId, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "SetupNonMemberOutsider");

        var shares = BuildShares(outsiderId);
        var response = await ownerClient.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 2,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupTrustees_NoRecoverySetup_ReturnsNotFound()
    {
        // A user without a base recovery setup cannot set trustees
        var (client, _, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "SetupNoBaseSetup");
        var trustee = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NoBaseSetupTrustee1");
        var trustee2 = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NoBaseSetupTrustee2");

        var shares = BuildShares(trustee.UserId, trustee2.UserId);
        var response = await client.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 2,
            shares
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SetupTrustees_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/recovery/trustees/setup", new
        {
            threshold = 2,
            shares = Array.Empty<object>()
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── GET /api/recovery/trustees ─────────────────────────────────────────────

    [Fact]
    public async Task ListTrustees_AfterSetup_ReturnsTrustees()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ListAfterSetup");

        await SetupTrusteesAsync(ownerClient, trustees);

        var response = await ownerClient.GetAsync("/api/recovery/trustees");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var trusteeArray = body.GetProperty("trustees");
        Assert.Equal(3, trusteeArray.GetArrayLength());
        Assert.Equal(2, body.GetProperty("threshold").GetInt32());
    }

    [Fact]
    public async Task ListTrustees_NoSetup_ReturnsEmpty()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ListNoSetup");

        var response = await client.GetAsync("/api/recovery/trustees");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(0, body.GetProperty("trustees").GetArrayLength());
        Assert.Equal(0, body.GetProperty("threshold").GetInt32());
    }

    [Fact]
    public async Task ListTrustees_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/recovery/trustees");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── POST /api/recovery/requests (public) ──────────────────────────────────

    [Fact]
    public async Task CreateRecoveryRequest_ValidDid_ReturnsPending()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("CreateReqValid");
        await SetupTrusteesAsync(ownerClient, trustees);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did = ownerDid }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("pending", body.GetProperty("status").GetString());
        Assert.True(body.TryGetProperty("request_id", out _));
        Assert.True(body.TryGetProperty("expires_at", out _));
    }

    [Fact]
    public async Task CreateRecoveryRequest_UnknownDid_ReturnsNotFound()
    {
        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did = "did:ssdid:no-such-user-trustee-test" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task CreateRecoveryRequest_DuplicateRequest_Returns409()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("CreateReqDup");
        await SetupTrusteesAsync(ownerClient, trustees);

        var anonClient = _factory.CreateClient();
        // First request
        var first = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did = ownerDid }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        // Second request — duplicate
        var second = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did = ownerDid }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task CreateRecoveryRequest_NoSetup_ReturnsNotFound()
    {
        // User exists but has not set up trustee recovery
        var did = $"did:ssdid:createreq-nosetup-{Guid.NewGuid():N}";
        await TestFixture.CreateAuthenticatedClientAsync(_factory, "CreateReqNoSetup", did: did);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task CreateRecoveryRequest_NoTrustees_ReturnsNotFound()
    {
        // User has a base recovery setup but no trustees configured
        var did = $"did:ssdid:createreq-notrustees-{Guid.NewGuid():N}";
        var (ownerClient, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "CreateReqNoTrustees", did: did);

        // Create base recovery setup but skip SetupTrustees
        var setupResp = await ownerClient.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('q', 64)
        }, TestFixture.Json);
        setupResp.EnsureSuccessStatusCode();

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync("/api/recovery/requests",
            new { did }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── GET /api/recovery/requests/pending ────────────────────────────────────

    [Fact]
    public async Task GetPendingRequests_AsTrustee_ReturnsRequests()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("PendingAsTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        await CreateRecoveryRequestAsync(ownerDid);

        // Trustee 1 checks pending requests
        var response = await trustees[0].Client.GetAsync("/api/recovery/requests/pending");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var requests = body.GetProperty("requests");
        Assert.True(requests.GetArrayLength() > 0);
    }

    [Fact]
    public async Task GetPendingRequests_NotTrustee_ReturnsEmpty()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("PendingNotTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        await CreateRecoveryRequestAsync(ownerDid);

        // A completely different user (not a trustee) should see no requests
        var (nonTrusteeClient, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "PendingNotTrusteeUser");
        var response = await nonTrusteeClient.GetAsync("/api/recovery/requests/pending");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(0, body.GetProperty("requests").GetArrayLength());
    }

    [Fact]
    public async Task GetPendingRequests_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/recovery/requests/pending");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── POST /api/recovery/requests/{id}/approve ──────────────────────────────

    [Fact]
    public async Task ApproveRequest_AsTrustee_ReturnsOk()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ApproveAsTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var response = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(requestId, body.GetProperty("request_id").GetGuid());
        Assert.Equal(1, body.GetProperty("approved_count").GetInt32());
    }

    [Fact]
    public async Task ApproveRequest_NotTrustee_Returns403()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ApproveNotTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var (nonTrusteeClient, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ApproveNotTrusteeUser");

        var response = await nonTrusteeClient.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ApproveRequest_SelfApproval_Returns403()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ApproveSelf");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // The owner (requester) tries to approve their own request
        var response = await ownerClient.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ApproveRequest_ThresholdMet_StatusApproved()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ApproveThreshold");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // First approval
        var first = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        // Second approval — should meet threshold
        var second = await trustees[1].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);

        var body = await second.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("approved", body.GetProperty("status").GetString());
        Assert.Equal(2, body.GetProperty("approved_count").GetInt32());
    }

    [Fact]
    public async Task ApproveRequest_AlreadyDecided_Returns409()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("ApproveAlreadyDecided");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // First approval succeeds
        var first = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        // Second attempt by the same trustee → conflict
        var second = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task ApproveRequest_NonExistentRequest_ReturnsNotFound()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ApproveNonExistent");

        var response = await client.PostAsync(
            $"/api/recovery/requests/{Guid.NewGuid()}/approve", null);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── POST /api/recovery/requests/{id}/reject ───────────────────────────────

    [Fact]
    public async Task RejectRequest_AsTrustee_ReturnsOk()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("RejectAsTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var response = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/reject", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(requestId, body.GetProperty("request_id").GetGuid());
        Assert.Equal("rejected", body.GetProperty("decision").GetString());
    }

    [Fact]
    public async Task RejectRequest_NotTrustee_Returns403()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("RejectNotTrustee");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var (nonTrusteeClient, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "RejectNotTrusteeUser");

        var response = await nonTrusteeClient.PostAsync(
            $"/api/recovery/requests/{requestId}/reject", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RejectRequest_SelfRejection_Returns403()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("RejectSelf");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var response = await ownerClient.PostAsync(
            $"/api/recovery/requests/{requestId}/reject", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RejectRequest_AlreadyDecided_Returns409()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("RejectAlreadyDecided");
        await SetupTrusteesAsync(ownerClient, trustees);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        var first = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/reject", null);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        var second = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/reject", null);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task RejectRequest_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsync(
            $"/api/recovery/requests/{Guid.NewGuid()}/reject", null);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── GET /api/recovery/requests/{id}/shares (public) ───────────────────────

    [Fact]
    public async Task GetReleasedShares_Approved_ReturnsShares()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SharesApproved");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // Approve threshold (2)
        await trustees[0].Client.PostAsync($"/api/recovery/requests/{requestId}/approve", null);
        await trustees[1].Client.PostAsync($"/api/recovery/requests/{requestId}/approve", null);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync(
            $"/api/recovery/requests/{requestId}/shares?did={Uri.EscapeDataString(ownerDid)}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("approved", body.GetProperty("status").GetString());
        var shares = body.GetProperty("shares");
        Assert.Equal(2, shares.GetArrayLength());
    }

    [Fact]
    public async Task GetReleasedShares_NotApproved_ReturnsBadRequest()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SharesNotApproved");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // Only 1 approval — not enough to meet threshold=2
        await trustees[0].Client.PostAsync($"/api/recovery/requests/{requestId}/approve", null);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync(
            $"/api/recovery/requests/{requestId}/shares?did={Uri.EscapeDataString(ownerDid)}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task GetReleasedShares_WrongDid_Returns403()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SharesWrongDid");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);
        var requestId = await CreateRecoveryRequestAsync(ownerDid);

        // Approve threshold
        await trustees[0].Client.PostAsync($"/api/recovery/requests/{requestId}/approve", null);
        await trustees[1].Client.PostAsync($"/api/recovery/requests/{requestId}/approve", null);

        var anonClient = _factory.CreateClient();
        var wrongDid = "did:ssdid:wrong-did-for-shares-test";
        var response = await anonClient.GetAsync(
            $"/api/recovery/requests/{requestId}/shares?did={Uri.EscapeDataString(wrongDid)}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetReleasedShares_Expired_Returns410()
    {
        var (ownerClient, ownerId, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("SharesExpired");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);

        // Directly insert an already-expired request that is approved
        Guid requestId;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            var setup = await db.RecoverySetups
                .Where(rs => rs.UserId == ownerId && rs.IsActive)
                .FirstAsync();

            var req = new RecoveryRequest
            {
                Id = Guid.NewGuid(),
                RequesterId = ownerId,
                RecoverySetupId = setup.Id,
                Status = RecoveryRequestStatus.Approved,
                ApprovedCount = 2,
                RequiredCount = 2,
                ExpiresAt = DateTimeOffset.UtcNow.AddHours(-1), // already expired
                CreatedAt = DateTimeOffset.UtcNow.AddHours(-50)
            };
            db.RecoveryRequests.Add(req);
            await db.SaveChangesAsync();
            requestId = req.Id;
        }

        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync(
            $"/api/recovery/requests/{requestId}/shares?did={Uri.EscapeDataString(ownerDid)}");

        Assert.Equal(HttpStatusCode.Gone, response.StatusCode);
    }

    [Fact]
    public async Task GetReleasedShares_NonExistentRequest_ReturnsNotFound()
    {
        var anonClient = _factory.CreateClient();
        var response = await anonClient.GetAsync(
            $"/api/recovery/requests/{Guid.NewGuid()}/shares?did=did:ssdid:any");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── POST /api/recovery/requests/initiate ──────────────────────────────────

    [Fact]
    public async Task InitiateRequest_WithSetup_ReturnsOk()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("InitiateWithSetup");
        await SetupTrusteesAsync(ownerClient, trustees);

        var response = await ownerClient.PostAsync("/api/recovery/requests/initiate", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("pending", body.GetProperty("status").GetString());
        Assert.True(body.TryGetProperty("request_id", out _));
        Assert.True(body.TryGetProperty("expires_at", out _));
    }

    [Fact]
    public async Task InitiateRequest_NoSetup_Returns404()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "InitiateNoSetup");

        var response = await client.PostAsync("/api/recovery/requests/initiate", null);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task InitiateRequest_BaseSetupButNoTrustees_Returns404()
    {
        var (ownerClient, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "InitiateNoTrustees");

        // Only base recovery setup, no trustees
        var setupResp = await ownerClient.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('r', 64)
        }, TestFixture.Json);
        setupResp.EnsureSuccessStatusCode();

        var response = await ownerClient.PostAsync("/api/recovery/requests/initiate", null);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task InitiateRequest_DuplicatePending_Returns409()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("InitiateDuplicate");
        await SetupTrusteesAsync(ownerClient, trustees);

        var first = await ownerClient.PostAsync("/api/recovery/requests/initiate", null);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        var second = await ownerClient.PostAsync("/api/recovery/requests/initiate", null);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task InitiateRequest_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsync("/api/recovery/requests/initiate", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── GET /api/recovery/requests/mine ───────────────────────────────────────

    [Fact]
    public async Task GetMyRequest_HasPending_ReturnsRequest()
    {
        var (ownerClient, _, _, _, trustees) =
            await CreateOwnerWithTrusteesAsync("MyRequestHasPending");
        await SetupTrusteesAsync(ownerClient, trustees);

        await ownerClient.PostAsync("/api/recovery/requests/initiate", null);

        var response = await ownerClient.GetAsync("/api/recovery/requests/mine");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var req = body.GetProperty("request");
        Assert.NotEqual(JsonValueKind.Null, req.ValueKind);
        Assert.Equal("pending", req.GetProperty("status").GetString());
        Assert.True(req.TryGetProperty("id", out _));
        Assert.True(req.TryGetProperty("expires_at", out _));
    }

    [Fact]
    public async Task GetMyRequest_NoPending_ReturnsNull()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "MyRequestNoPending");

        var response = await client.GetAsync("/api/recovery/requests/mine");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var req = body.GetProperty("request");
        Assert.Equal(JsonValueKind.Null, req.ValueKind);
    }

    [Fact]
    public async Task GetMyRequest_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/recovery/requests/mine");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── Cross-endpoint flow ────────────────────────────────────────────────────

    [Fact]
    public async Task FullTrusteeRecoveryFlow_SetupToApprovedShares()
    {
        var (ownerClient, _, ownerDid, _, trustees) =
            await CreateOwnerWithTrusteesAsync("FullFlow");
        await SetupTrusteesAsync(ownerClient, trustees, threshold: 2);

        // 1. Trustee list shows 3 trustees
        var listResp = await ownerClient.GetAsync("/api/recovery/trustees");
        var listBody = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, listBody.GetProperty("trustees").GetArrayLength());

        // 2. Owner initiates recovery
        var initiateResp = await ownerClient.PostAsync("/api/recovery/requests/initiate", null);
        Assert.Equal(HttpStatusCode.OK, initiateResp.StatusCode);
        var initiateBody = await initiateResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var requestId = initiateBody.GetProperty("request_id").GetGuid();

        // 3. Both trustees see the pending request
        var pending1Resp = await trustees[0].Client.GetAsync("/api/recovery/requests/pending");
        var pending1Body = await pending1Resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(1, pending1Body.GetProperty("requests").GetArrayLength());

        // 4. Two trustees approve (meets threshold=2)
        var approveResp1 = await trustees[0].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.OK, approveResp1.StatusCode);

        var approveResp2 = await trustees[1].Client.PostAsync(
            $"/api/recovery/requests/{requestId}/approve", null);
        Assert.Equal(HttpStatusCode.OK, approveResp2.StatusCode);
        var approveBody2 = await approveResp2.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("approved", approveBody2.GetProperty("status").GetString());

        // 5. Owner checks /mine — status is approved
        var mineResp = await ownerClient.GetAsync("/api/recovery/requests/mine");
        var mineBody = await mineResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("approved", mineBody.GetProperty("request").GetProperty("status").GetString());

        // 6. Shares are retrievable
        var sharesResp = await _factory.CreateClient().GetAsync(
            $"/api/recovery/requests/{requestId}/shares?did={Uri.EscapeDataString(ownerDid)}");
        Assert.Equal(HttpStatusCode.OK, sharesResp.StatusCode);
        var sharesBody = await sharesResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(2, sharesBody.GetProperty("shares").GetArrayLength());

        // 7. After approval the pending list for trustee[0] no longer shows this request
        var afterPendingResp = await trustees[0].Client.GetAsync("/api/recovery/requests/pending");
        var afterPendingBody = await afterPendingResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        // trustee[0] already decided, so it won't appear again
        Assert.Equal(0, afterPendingBody.GetProperty("requests").GetArrayLength());
    }
}
