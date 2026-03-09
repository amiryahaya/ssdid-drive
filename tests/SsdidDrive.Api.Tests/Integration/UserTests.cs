using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class UserTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public UserTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task GetProfile_ReturnsCurrentUser()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Alice");

        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(userId, body.GetProperty("id").GetGuid());
        Assert.Equal("Alice", body.GetProperty("display_name").GetString());
        Assert.Equal("active", body.GetProperty("status").GetString());
        Assert.True(body.TryGetProperty("created_at", out _));
    }

    [Fact]
    public async Task UpdateProfile_ChangesDisplayName()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "OldName");

        var patchResponse = await client.PatchAsJsonAsync("/api/me",
            new { display_name = "NewName" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, patchResponse.StatusCode);

        var putBody = await patchResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("NewName", putBody.GetProperty("display_name").GetString());

        // Verify change persisted via GET
        var getResponse = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

        var getBody = await getResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("NewName", getBody.GetProperty("display_name").GetString());
        Assert.Equal(userId, getBody.GetProperty("id").GetGuid());
    }

    [Fact]
    public async Task UpdateKeys_StoresAndRetrieves()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KeyUser");

        var masterKey = Convert.ToBase64String("test-master-key-bytes"u8.ToArray());
        var privateKeys = Convert.ToBase64String("test-private-keys-bytes"u8.ToArray());
        var salt = Convert.ToBase64String("test-salt-bytes"u8.ToArray());
        var publicKeys = "{\"kem\":\"test-pub\",\"sign\":\"test-sign\"}";

        var patchResponse = await client.PatchAsJsonAsync("/api/me/keys", new
        {
            public_keys = publicKeys,
            encrypted_master_key = masterKey,
            encrypted_private_keys = privateKeys,
            key_derivation_salt = salt
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, patchResponse.StatusCode);

        // Verify keys persisted via GET
        var getResponse = await client.GetAsync("/api/me/keys");
        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

        var body = await getResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(publicKeys, body.GetProperty("public_keys").GetString());
        Assert.Equal(masterKey, body.GetProperty("encrypted_master_key").GetString());
        Assert.Equal(privateKeys, body.GetProperty("encrypted_private_keys").GetString());
        Assert.Equal(salt, body.GetProperty("key_derivation_salt").GetString());
    }

    [Fact]
    public async Task GetPublicKey_CrossUser_ReturnsPublicKeys()
    {
        // Create a user and set their public keys
        var (client1, userId1, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Publisher");
        var publicKeys = "{\"kem\":\"pub-kem-key\"}";
        await client1.PatchAsJsonAsync("/api/me/keys", new { public_keys = publicKeys }, TestFixture.Json);

        // A different authenticated user can fetch the first user's public key
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Consumer");
        var response = await client2.GetAsync($"/api/users/{userId1}/public-key");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(userId1, body.GetProperty("id").GetGuid());
        Assert.Equal(publicKeys, body.GetProperty("public_keys").GetString());
    }

    [Fact]
    public async Task GetPublicKey_NonExistentUser_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.GetAsync($"/api/users/{Guid.NewGuid()}/public-key");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task PublishAndGetKemKey_RoundTrips()
    {
        var (client1, userId1, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KemPublisher");
        var kemPk = Convert.ToBase64String(new byte[32]);

        var publishResponse = await client1.PatchAsJsonAsync("/api/me/keys/kem",
            new { kem_public_key = kemPk, kem_algorithm = "ML-KEM-768" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, publishResponse.StatusCode);

        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KemConsumer");
        var getResponse = await client2.GetAsync($"/api/users/{userId1}/kem-public-key");
        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

        var body = await getResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(kemPk, body.GetProperty("kem_public_key").GetString());
        Assert.Equal("ML-KEM-768", body.GetProperty("kem_algorithm").GetString());
    }

    [Fact]
    public async Task GetKemPublicKey_NoKeySet_Returns404()
    {
        var (client1, userId1, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NoKemUser");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KemLooker");

        var response = await client2.GetAsync($"/api/users/{userId1}/kem-public-key");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ListTenantUsers_ReturnsUsersInSameTenant()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantUser");

        var response = await client.GetAsync("/api/users");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var users = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(users.GetArrayLength() >= 1);

        var ids = Enumerable.Range(0, users.GetArrayLength())
            .Select(i => users[i].GetProperty("id").GetGuid())
            .ToList();
        Assert.Contains(userId, ids);

        // Verify display_name is present
        var displayNames = Enumerable.Range(0, users.GetArrayLength())
            .Select(i => users[i].GetProperty("display_name").GetString())
            .ToList();
        Assert.Contains("TenantUser", displayNames);
    }
}
