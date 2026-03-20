using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests for the 5 Shamir-recovery endpoints:
///   POST   /api/recovery/setup
///   GET    /api/recovery/status
///   DELETE /api/recovery/setup
///   GET    /api/recovery/share?did=…
///   POST   /api/recovery/complete
/// </summary>
public class RecoveryShamirTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public RecoveryShamirTests(SsdidDriveFactory factory) => _factory = factory;

    // ── POST /api/recovery/setup ──────────────────────────────────────

    [Fact]
    public async Task SetupRecovery_ReturnsCreated()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirSetupUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('a', 64)
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task SetupRecovery_EmptyServerShare_ReturnsBadRequest()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirEmptyShareUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = "",
            key_proof = new string('a', 64)
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupRecovery_ShortKeyProof_ReturnsBadRequest()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirBadProofUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = "too-short"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupRecovery_LongKeyProof_ReturnsBadRequest()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirLongProofUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('z', 65)   // one character too long
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SetupRecovery_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('a', 64)
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── GET /api/recovery/status ──────────────────────────────────────

    [Fact]
    public async Task GetRecoveryStatus_AfterSetup_ReturnsIsActiveTrue()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirStatusActiveUser");

        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('b', 64)
        }, TestFixture.Json);

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.GetProperty("is_active").GetBoolean());
        Assert.True(body.TryGetProperty("created_at", out _));
    }

    [Fact]
    public async Task GetRecoveryStatus_NoSetup_ReturnsIsActiveFalse()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirStatusInactiveUser");

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(body.GetProperty("is_active").GetBoolean());
    }

    [Fact]
    public async Task GetRecoveryStatus_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── DELETE /api/recovery/setup ────────────────────────────────────

    [Fact]
    public async Task DeleteRecoverySetup_AfterSetup_DeactivatesAndReturnsNoContent()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirDeleteUser");

        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('c', 64)
        }, TestFixture.Json);

        var deleteResponse = await client.DeleteAsync("/api/recovery/setup");
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        // Status should now show inactive
        var statusResponse = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, statusResponse.StatusCode);
        var body = await statusResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(body.GetProperty("is_active").GetBoolean());
    }

    [Fact]
    public async Task DeleteRecoverySetup_NoExistingSetup_ReturnsNoContent()
    {
        // Delete is idempotent — no setup exists but it should still return 204
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirDeleteNoSetupUser");

        var response = await client.DeleteAsync("/api/recovery/setup");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task DeleteRecoverySetup_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        var response = await client.DeleteAsync("/api/recovery/setup");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ── GET /api/recovery/share?did=… ────────────────────────────────

    [Fact]
    public async Task GetRecoveryShare_KnownDid_ReturnsShareAndIndex()
    {
        // Create a user with a known DID and set up recovery
        var knownDid = $"did:ssdid:test-shamir-share-{Guid.NewGuid():N}";
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirShareOwner", did: knownDid);

        var serverShare = Convert.ToBase64String(new byte[32]);
        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = serverShare,
            key_proof = new string('e', 64)
        }, TestFixture.Json);

        // Retrieval by DID (requires auth)
        var (shareClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareRetriever");
        var response = await shareClient.GetAsync(
            $"/api/recovery/share?did={Uri.EscapeDataString(knownDid)}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(serverShare, body.GetProperty("server_share").GetString());
        Assert.Equal(3, body.GetProperty("share_index").GetInt32());
    }

    [Fact]
    public async Task GetRecoveryShare_UnknownDid_ReturnsNotFound()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareUnknownUser");
        var response = await client.GetAsync(
            "/api/recovery/share?did=did:ssdid:no-such-user-xyz");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetRecoveryShare_DeletedSetup_ReturnsNotFound()
    {
        var deletedDid = $"did:ssdid:test-shamir-deleted-{Guid.NewGuid():N}";
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirShareDeletedOwner", did: deletedDid);

        // Setup then delete
        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('f', 64)
        }, TestFixture.Json);
        await client.DeleteAsync("/api/recovery/setup");

        // The share should no longer be findable
        var (lookupClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareDeletedLooker");
        var response = await lookupClient.GetAsync(
            $"/api/recovery/share?did={Uri.EscapeDataString(deletedDid)}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── POST /api/recovery/complete ───────────────────────────────────

    [Fact]
    public async Task CompleteRecovery_ValidKeyProof_ReturnsOkWithToken()
    {
        var oldDid = $"did:ssdid:test-shamir-complete-{Guid.NewGuid():N}";
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirCompleteUser", did: oldDid);

        var keyProof = new string('d', 64);
        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = keyProof
        }, TestFixture.Json);

        var newDid = $"did:ssdid:test-shamir-newdevice-{Guid.NewGuid():N}";
        var (completeClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirCompleter");
        var response = await completeClient.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = oldDid,
            new_did = newDid,
            key_proof = keyProof,
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("session_token", out var tokenProp));
        Assert.False(string.IsNullOrEmpty(tokenProp.GetString()));
        Assert.True(body.TryGetProperty("user_id", out _));
    }

    [Fact]
    public async Task CompleteRecovery_WrongKeyProof_ReturnsForbidden()
    {
        var oldDid = $"did:ssdid:test-shamir-wrongproof-{Guid.NewGuid():N}";
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirWrongProofUser", did: oldDid);

        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('d', 64)
        }, TestFixture.Json);

        var (wrongProofClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirWrongProofer");
        var response = await wrongProofClient.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = oldDid,
            new_did = $"did:ssdid:test-shamir-wrong-{Guid.NewGuid():N}",
            key_proof = new string('x', 64),   // wrong proof
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task CompleteRecovery_UnknownOldDid_ReturnsNotFound()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirUnknownDid");
        var response = await client.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = "did:ssdid:no-such-user-complete",
            new_did = "did:ssdid:some-new-device",
            key_proof = new string('a', 64),
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task CompleteRecovery_MissingFields_ReturnsBadRequest()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirMissingFields");
        var response = await client.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = "",
            new_did = "",
            key_proof = "",
            kem_public_key = ""
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CompleteRecovery_NoActiveSetup_ReturnsNotFound()
    {
        // User exists but has never set up recovery
        var oldDid = $"did:ssdid:test-shamir-nosetup-{Guid.NewGuid():N}";
        await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirNoSetupComplete", did: oldDid);

        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirNoSetupCompleter");
        var response = await client.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = oldDid,
            new_did = $"did:ssdid:test-shamir-ns-new-{Guid.NewGuid():N}",
            key_proof = new string('a', 64),
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── Cross-endpoint flow ────────────────────────────────────────────

    [Fact]
    public async Task FullRecoveryFlow_SetupThenCompleteInvalidatesSetup()
    {
        var oldDid = $"did:ssdid:test-shamir-flow-{Guid.NewGuid():N}";
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
            _factory, "ShamirFlowUser", did: oldDid);

        var keyProof = new string('g', 64);

        // 1. Setup
        var setupResp = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = keyProof
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, setupResp.StatusCode);

        // 2. Status is active
        var statusResp = await client.GetAsync("/api/recovery/status");
        var statusBody = await statusResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(statusBody.GetProperty("is_active").GetBoolean());

        // 3. Complete recovery
        var newDid = $"did:ssdid:test-shamir-flow-new-{Guid.NewGuid():N}";
        var (flowCompleteClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShamirFlowCompleter");
        var completeResp = await flowCompleteClient.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = oldDid,
            new_did = newDid,
            key_proof = keyProof,
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, completeResp.StatusCode);

        // 4. Share is no longer available — setup was deactivated
        var shareResp = await flowCompleteClient.GetAsync(
            $"/api/recovery/share?did={Uri.EscapeDataString(oldDid)}");
        Assert.Equal(HttpStatusCode.NotFound, shareResp.StatusCode);
    }
}
