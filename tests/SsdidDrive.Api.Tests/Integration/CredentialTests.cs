using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class CredentialTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public CredentialTests(SsdidDriveFactory factory) => _factory = factory;

    // ── Helper: register a credential via begin + complete flow ──────────

    private async Task<JsonElement> RegisterCredentialAsync(HttpClient client, string name = "My Device")
    {
        // Begin
        var beginResp = await client.PostAsync("/api/credentials/webauthn/begin", null);
        Assert.Equal(HttpStatusCode.OK, beginResp.StatusCode);
        var beginBody = await beginResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var challenge = beginBody.GetProperty("challenge").GetString();
        Assert.False(string.IsNullOrEmpty(challenge));

        // Complete
        var completeReq = new
        {
            credential_id = Convert.ToBase64String(Guid.NewGuid().ToByteArray()),
            public_key = Convert.ToBase64String(new byte[65]),
            name
        };
        var completeResp = await client.PostAsJsonAsync("/api/credentials/webauthn/complete", completeReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, completeResp.StatusCode);

        return await completeResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    }

    // ── 1. Begin WebAuthn registration → 200 with challenge ─────────────

    [Fact]
    public async Task BeginAddCredential_ReturnsChallenge()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredBegin");

        var response = await client.PostAsync("/api/credentials/webauthn/begin", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(string.IsNullOrEmpty(body.GetProperty("challenge").GetString()));
        Assert.Equal("SSDID Drive", body.GetProperty("rp").GetProperty("name").GetString());
        Assert.Equal("drive.ssdid.my", body.GetProperty("rp").GetProperty("id").GetString());
        Assert.Equal(60000, body.GetProperty("timeout").GetInt32());
        Assert.Equal("none", body.GetProperty("attestation").GetString());
    }

    // ── 2. Complete WebAuthn registration → 201 ─────────────────────────

    [Fact]
    public async Task CompleteAddCredential_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredComplete");

        var cred = await RegisterCredentialAsync(client, "Test Passkey");

        Assert.Equal("Test Passkey", cred.GetProperty("name").GetString());
        Assert.NotEqual(Guid.Empty, cred.GetProperty("id").GetGuid());
        Assert.False(string.IsNullOrEmpty(cred.GetProperty("credential_id").GetString()));
        // public_key must NOT be exposed in response
        Assert.False(cred.TryGetProperty("public_key", out _));
    }

    // ── 3. List credentials → 200 with registered credential ────────────

    [Fact]
    public async Task ListCredentials_ReturnsRegisteredCredentials()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredList");

        await RegisterCredentialAsync(client, "Device A");
        await RegisterCredentialAsync(client, "Device B");

        var response = await client.GetAsync("/api/credentials");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var creds = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(creds.GetArrayLength() >= 2);

        var names = Enumerable.Range(0, creds.GetArrayLength())
            .Select(i => creds[i].GetProperty("name").GetString())
            .ToList();
        Assert.Contains("Device A", names);
        Assert.Contains("Device B", names);

        // Verify public_key is NOT in list response
        var first = creds[0];
        Assert.False(first.TryGetProperty("public_key", out _));
    }

    // ── 4. Rename credential → 200 ──────────────────────────────────────

    [Fact]
    public async Task RenameCredential_ReturnsOk()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredRename");

        var cred = await RegisterCredentialAsync(client, "Old Name");
        var credId = cred.GetProperty("id").GetGuid();

        var renameReq = new { name = "New Name" };
        var response = await client.PatchAsJsonAsync($"/api/credentials/{credId}", renameReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("New Name", body.GetProperty("name").GetString());
    }

    // ── 5. Delete credential → 204 ──────────────────────────────────────

    [Fact]
    public async Task DeleteCredential_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredDelete");

        // Register two so we can delete one (must keep at least 1)
        await RegisterCredentialAsync(client, "Keep Me");
        var toDelete = await RegisterCredentialAsync(client, "Delete Me");
        var deleteId = toDelete.GetProperty("id").GetGuid();

        var response = await client.DeleteAsync($"/api/credentials/{deleteId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify it's gone
        var listResp = await client.GetAsync("/api/credentials");
        var creds = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var ids = Enumerable.Range(0, creds.GetArrayLength())
            .Select(i => creds[i].GetProperty("id").GetGuid())
            .ToList();
        Assert.DoesNotContain(deleteId, ids);
    }

    // ── 6. Delete last credential → 400 ─────────────────────────────────

    [Fact]
    public async Task DeleteCredential_LastOne_ReturnsBadRequest()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredDeleteLast");

        var cred = await RegisterCredentialAsync(client, "Only One");
        var credId = cred.GetProperty("id").GetGuid();

        var response = await client.DeleteAsync($"/api/credentials/{credId}");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 7. Delete credential as non-owner → 404 ─────────────────────────

    [Fact]
    public async Task DeleteCredential_NonOwner_ReturnsNotFound()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "CredOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "CredNonOwner");

        var cred = await RegisterCredentialAsync(client1, "Owner's Key");
        var credId = cred.GetProperty("id").GetGuid();

        // Non-owner tries to delete → 404 (don't reveal existence)
        var response = await client2.DeleteAsync($"/api/credentials/{credId}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
