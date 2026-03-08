using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests that hit the real SSDID registry (https://registry.ssdid.my).
///
/// Part 1: Direct registry tests — verify our RegistryClient, SsdidIdentity,
/// and W3C Data Integrity proof construction work with the live registry.
///
/// Part 2: Full API stack tests — backend endpoints (/api/auth/ssdid/register,
/// /register/verify, /authenticate) with the real registry as the DID resolver.
///
/// KAZ-Sign: C library (v3.0) uses kaz-pqc-core-v2.0 algorithm (g1=65537, g2=65539),
/// matching the deployed registry JARs. SPKI + KazWire encoding is used for interop.
///
/// Skip if registry is unreachable (offline, CI without network, etc.).
/// </summary>
public class RegistryIntegrationTests
{
    private const string RegistryUrl = "https://registry.ssdid.my";

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

    private static CryptoProviderFactory CreateCryptoFactory()
    {
        var providers = new ICryptoProvider[]
        {
            new Ed25519Provider(),
            new EcdsaProvider(),
            new MlDsaProvider(),
            new SlhDsaProvider(),
            new KazSignProvider(),
        };
        return new CryptoProviderFactory(providers);
    }

    private static void SkipIfRegistryUnavailable()
    {
        try
        {
            var resp = Http.GetAsync($"{RegistryUrl}/api/did/test").Result;
            // Any response (even 404) means registry is reachable
        }
        catch
        {
            Assert.Skip("SSDID registry is unreachable");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Part 1: Direct Registry Tests
    // ════════════════════════════════════════════════════════════════════

    // ── Test 1: Register DID with real registry (Ed25519) ──

    [Fact]
    public async Task RegisterDid_Ed25519_Succeeds()
    {
        SkipIfRegistryUnavailable();
        await RegisterAndResolve("Ed25519VerificationKey2020");
    }

    // ── Tests 2-4: PQC algorithms ──

    [Fact]
    public async Task RegisterDid_MlDsa44_Succeeds()
    {
        SkipIfRegistryUnavailable();
        await RegisterAndResolve("MlDsa44VerificationKey2024");
    }

    [Fact]
    public async Task RegisterDid_MlDsa65_Succeeds()
    {
        SkipIfRegistryUnavailable();
        await RegisterAndResolve("MlDsa65VerificationKey2024");
    }

    [Fact]
    public async Task RegisterDid_SlhDsaSha2128f_Succeeds()
    {
        SkipIfRegistryUnavailable();
        await RegisterAndResolve("SlhDsaSha2128fVerificationKey2024");
    }

    [Fact]
    public async Task RegisterDid_KazSign_Succeeds()
    {
        SkipIfRegistryUnavailable();
        PlatformFacts.SkipIfKazSignUnsupported();
        await RegisterAndResolve("KazSignVerificationKey2024");
    }

    // ── Test 6: Resolve unknown DID returns 404 ──

    [Fact]
    public async Task ResolveDid_UnknownDid_Returns404()
    {
        SkipIfRegistryUnavailable();

        var encodedDid = Uri.EscapeDataString("did:ssdid:nonexistent-test-did-12345");
        var resp = await Http.GetAsync($"{RegistryUrl}/api/did/{encodedDid}");

        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    // ── Test 7: Register with invalid proof fails ──

    [Fact]
    public async Task RegisterDid_InvalidProof_Fails()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        var didDoc = identity.BuildDidDocument();

        // Build proof with garbage signature
        var proof = new Dictionary<string, object>
        {
            ["type"] = "Ed25519Signature2020",
            ["created"] = DateTimeOffset.UtcNow.ToString("o"),
            ["verificationMethod"] = identity.KeyId,
            ["proofPurpose"] = "assertionMethod",
            ["proofValue"] = SsdidCrypto.MultibaseEncode(new byte[64])
        };

        var payload = new { did_document = didDoc, proof };
        var resp = await Http.PostAsJsonAsync($"{RegistryUrl}/api/did", payload);

        // Registry should reject invalid proof (not 2xx)
        Assert.False(resp.IsSuccessStatusCode,
            $"Expected rejection but got {resp.StatusCode}");
    }

    // ── Test 8: Full round-trip: register → resolve → verify key ──

    [Fact]
    public async Task FullRoundTrip_Ed25519_RegisterResolveVerify()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);

        // Register
        var (registered, regResponse) = await RegisterDid(identity, cryptoFactory);
        Assert.True(registered, $"DID registration failed: {regResponse}");

        // Resolve
        var encodedDid = Uri.EscapeDataString(identity.Did);
        var resolveResp = await Http.GetAsync($"{RegistryUrl}/api/did/{encodedDid}");
        Assert.Equal(HttpStatusCode.OK, resolveResp.StatusCode);

        var resolvedJson = await resolveResp.Content.ReadFromJsonAsync<JsonElement>();

        // Extract and verify public key
        var extracted = RegistryClient.ExtractPublicKey(resolvedJson, identity.KeyId);
        Assert.NotNull(extracted);

        var (resolvedPubKey, resolvedAlgType) = extracted.Value;
        Assert.Equal("Ed25519VerificationKey2020", resolvedAlgType);

        // Verify: sign something with our private key, verify with the resolved public key
        var message = "registry-roundtrip-test"u8.ToArray();
        var signature = cryptoFactory.Sign(identity.AlgorithmType, message, identity.PrivateKey);
        var verified = cryptoFactory.Verify(resolvedAlgType, message, signature, resolvedPubKey);

        Assert.True(verified, "Signature verification with resolved public key failed");
    }

    // ── Test 9: Server's ServerRegistrationService registers correctly ──

    [Fact]
    public async Task ServerRegistration_MatchesRegistryFormat()
    {
        SkipIfRegistryUnavailable();

        // Replicate what ServerRegistrationService does
        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);

        var didDoc = identity.BuildDidDocument();
        var proofType = CryptoProviderFactory.GetProofType(identity.AlgorithmType);
        var proofOptions = new Dictionary<string, object>
        {
            ["type"] = proofType,
            ["created"] = DateTimeOffset.UtcNow.ToString("o"),
            ["verificationMethod"] = identity.KeyId,
            ["proofPurpose"] = "assertionMethod"
        };

        var payload = SsdidCrypto.W3cSigningPayload(didDoc, proofOptions);
        var proofBytes = identity.SignRaw(payload);
        proofOptions["proofValue"] = SsdidCrypto.MultibaseEncode(proofBytes);

        var reqPayload = new { did_document = didDoc, proof = proofOptions };
        var resp = await Http.PostAsJsonAsync($"{RegistryUrl}/api/did", reqPayload);

        Assert.True(resp.IsSuccessStatusCode,
            $"Server registration format rejected: {resp.StatusCode} - {await resp.Content.ReadAsStringAsync()}");
    }

    // ── Test 10: KAZ-Sign local W3C proof round-trip ──

    [Fact]
    public void KazSign_LocalW3cProof_Succeeds()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create("KazSignVerificationKey2024", cryptoFactory);

        // Build DID document and proof (same flow as registry registration)
        var didDoc = identity.BuildDidDocument();
        var proofType = CryptoProviderFactory.GetProofType(identity.AlgorithmType);
        var proofOptions = new Dictionary<string, object>
        {
            ["type"] = proofType,
            ["created"] = DateTimeOffset.UtcNow.ToString("o"),
            ["verificationMethod"] = identity.KeyId,
            ["proofPurpose"] = "assertionMethod"
        };

        var payload = SsdidCrypto.W3cSigningPayload(didDoc, proofOptions);
        var proofBytes = identity.SignRaw(payload);

        // Verify the W3C proof locally (C library ↔ C library)
        var verified = cryptoFactory.Verify(identity.AlgorithmType, payload, proofBytes, identity.PublicKey);
        Assert.True(verified, "Local W3C proof verification failed");

        // Verify key sizes are correct for Level128
        Assert.Equal(79, identity.PublicKey.Length);    // SPKI: SEQUENCE { AlgID(15) BIT_STRING(62) } = 79
        Assert.Equal(32, identity.PrivateKey.Length);   // raw private key: s(16) + t(16)
        Assert.Equal(167, proofBytes.Length);            // KazWire sig: 5-byte header + S1(54) + S2(54) + S3(54)
    }

    // ════════════════════════════════════════════════════════════════════
    // Part 2: Backend API ↔ Registry Integration Tests
    //
    // These boot the full API stack (SsdidDriveFactory) but with the
    // RegistryClient pointing at the REAL registry instead of a mock.
    // This tests the complete auth flow: API endpoint → SsdidAuthService
    // → RegistryClient → real SSDID registry → DID Document resolution.
    // ════════════════════════════════════════════════════════════════════

    // ── Test 11: Full API auth flow with Ed25519 via real registry ──

    [Fact]
    public async Task ApiAuthFlow_Ed25519_RegisterVerifyAuthenticate()
    {
        SkipIfRegistryUnavailable();
        await RunApiAuthFlow("Ed25519VerificationKey2020");
    }

    // ── Test 12: Full API auth flow with ML-DSA-44 via real registry ──

    [Fact]
    public async Task ApiAuthFlow_MlDsa44_RegisterVerifyAuthenticate()
    {
        SkipIfRegistryUnavailable();
        await RunApiAuthFlow("MlDsa44VerificationKey2024");
    }

    // ── Test 13: Full API auth flow with ML-DSA-65 via real registry ──

    [Fact]
    public async Task ApiAuthFlow_MlDsa65_RegisterVerifyAuthenticate()
    {
        SkipIfRegistryUnavailable();
        await RunApiAuthFlow("MlDsa65VerificationKey2024");
    }

    // ── Test 14: Full API auth flow with SLH-DSA-SHA2-128f via real registry ──

    [Fact]
    public async Task ApiAuthFlow_SlhDsaSha2128f_RegisterVerifyAuthenticate()
    {
        SkipIfRegistryUnavailable();
        await RunApiAuthFlow("SlhDsaSha2128fVerificationKey2024");
    }

    // ── Test 15: Full API auth flow with KAZ-Sign via real registry ──

    [Fact]
    public async Task ApiAuthFlow_KazSign_RegisterVerifyAuthenticate()
    {
        SkipIfRegistryUnavailable();
        PlatformFacts.SkipIfKazSignUnsupported();
        await RunApiAuthFlow("KazSignVerificationKey2024");
    }

    // ── Test 16: API register with unregistered DID returns 404 ──

    [Fact]
    public async Task ApiRegister_UnregisteredDid_Returns404()
    {
        SkipIfRegistryUnavailable();

        await using var factory = new RealRegistryFactory();
        var client = factory.CreateClient();

        // Use a DID that doesn't exist in the registry
        var resp = await client.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = "did:ssdid:does-not-exist-in-registry", key_id = "did:ssdid:does-not-exist-in-registry#key-1" },
            SnakeJson);

        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    // ── Test 17: API authenticate with session token grants access ──

    [Fact]
    public async Task ApiAuthFlow_SessionToken_GrantsProtectedAccess()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var clientIdentity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);

        // Pre-register the client's DID in the real registry
        var (registered, regMsg) = await RegisterDid(clientIdentity, cryptoFactory);
        Assert.True(registered, $"Pre-registration failed: {regMsg}");

        await using var factory = new RealRegistryFactory();
        var httpClient = factory.CreateClient();

        // Step 1: Register via API (triggers registry resolution)
        var regResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        // Step 2: Sign challenge with client key
        var signedChallenge = clientIdentity.SignChallenge(challenge);

        // Step 3: Verify via API (triggers second registry resolution + signature check)
        var verifyResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge },
            SnakeJson);
        Assert.Equal(HttpStatusCode.Created, verifyResp.StatusCode);
        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        var credential = verifyBody.GetProperty("credential");

        // Step 4: Authenticate with the VC
        var authResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);
        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionToken = authBody.GetProperty("session_token").GetString()!;

        // Step 5: Use session token for protected endpoint
        httpClient.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sessionToken);
        var meResp = await httpClient.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, meResp.StatusCode);

        // Step 6: Logout and verify access revoked
        var logoutResp = await httpClient.PostAsync("/api/auth/ssdid/logout", null);
        Assert.Equal(HttpStatusCode.NoContent, logoutResp.StatusCode);

        var afterLogout = await httpClient.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, afterLogout.StatusCode);
    }

    // ── Test 18: API verify with wrong signature returns 401 ──

    [Fact]
    public async Task ApiVerify_WrongSignature_Returns401()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var clientIdentity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);

        // Pre-register client DID
        var (registered, _) = await RegisterDid(clientIdentity, cryptoFactory);
        Assert.True(registered);

        await using var factory = new RealRegistryFactory();
        var httpClient = factory.CreateClient();

        // Register via API
        var regResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);

        // Verify with garbage signature
        var fakeSignature = SsdidCrypto.MultibaseEncode(new byte[64]);
        var verifyResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = fakeSignature },
            SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, verifyResp.StatusCode);
    }

    // ── Test 19: API verify with different key's signature returns 401 ──

    [Fact]
    public async Task ApiVerify_DifferentKeySignature_Returns401()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var clientIdentity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);
        var wrongIdentity = SsdidIdentity.Create("Ed25519VerificationKey2020", cryptoFactory);

        // Pre-register client DID (not the wrong identity)
        var (registered, _) = await RegisterDid(clientIdentity, cryptoFactory);
        Assert.True(registered);

        await using var factory = new RealRegistryFactory();
        var httpClient = factory.CreateClient();

        // Register via API
        var regResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);
        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;

        // Sign with a DIFFERENT key (not the one in the registry)
        var wrongSignature = wrongIdentity.SignChallenge(challenge);

        var verifyResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = wrongSignature },
            SnakeJson);

        Assert.Equal(HttpStatusCode.Unauthorized, verifyResp.StatusCode);
    }

    // ── Test 20: ML-DSA-44 full round-trip: register → resolve → sign → verify ──

    [Fact]
    public async Task FullRoundTrip_MlDsa44_RegisterResolveVerify()
    {
        SkipIfRegistryUnavailable();

        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create("MlDsa44VerificationKey2024", cryptoFactory);

        var (registered, regResponse) = await RegisterDid(identity, cryptoFactory);
        Assert.True(registered, $"DID registration failed: {regResponse}");

        var encodedDid = Uri.EscapeDataString(identity.Did);
        var resolveResp = await Http.GetAsync($"{RegistryUrl}/api/did/{encodedDid}");
        Assert.Equal(HttpStatusCode.OK, resolveResp.StatusCode);

        var resolvedJson = await resolveResp.Content.ReadFromJsonAsync<JsonElement>();
        var extracted = RegistryClient.ExtractPublicKey(resolvedJson, identity.KeyId);
        Assert.NotNull(extracted);

        var (resolvedPubKey, resolvedAlgType) = extracted.Value;
        Assert.Equal("MlDsa44VerificationKey2024", resolvedAlgType);

        var message = "pqc-roundtrip-test"u8.ToArray();
        var signature = cryptoFactory.Sign(identity.AlgorithmType, message, identity.PrivateKey);
        var verified = cryptoFactory.Verify(resolvedAlgType, message, signature, resolvedPubKey);

        Assert.True(verified, "ML-DSA-44 signature verification with resolved public key failed");
    }

    // ════════════════════════════════════════════════════════════════════
    // Shared helpers
    // ════════════════════════════════════════════════════════════════════

    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    /// <summary>
    /// Runs the complete API auth flow (register → verify → authenticate)
    /// with the given algorithm against the real registry.
    /// </summary>
    private static async Task RunApiAuthFlow(string algorithmType)
    {
        var cryptoFactory = CreateCryptoFactory();
        var clientIdentity = SsdidIdentity.Create(algorithmType, cryptoFactory);

        // Pre-register the client's DID in the real registry
        var (registered, regMsg) = await RegisterDid(clientIdentity, cryptoFactory);
        Assert.True(registered, $"Pre-registration failed for {algorithmType}: {regMsg}");

        await using var factory = new RealRegistryFactory();
        var httpClient = factory.CreateClient();

        // Step 1: Register via API → triggers RegistryClient.ResolveDid
        var regResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId },
            SnakeJson);
        Assert.Equal(HttpStatusCode.OK, regResp.StatusCode);

        var regBody = await regResp.Content.ReadFromJsonAsync<JsonElement>();
        var challenge = regBody.GetProperty("challenge").GetString()!;
        Assert.False(string.IsNullOrEmpty(challenge));

        // Verify server DID is returned
        Assert.True(regBody.TryGetProperty("server_did", out var serverDid));
        Assert.StartsWith("did:ssdid:", serverDid.GetString());
        Assert.True(regBody.TryGetProperty("server_signature", out _));

        // Step 2: Client signs the challenge
        var signedChallenge = clientIdentity.SignChallenge(challenge);

        // Step 3: Verify via API → second registry resolution + signature verification
        var verifyResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/register/verify",
            new { did = clientIdentity.Did, key_id = clientIdentity.KeyId, signed_challenge = signedChallenge },
            SnakeJson);
        Assert.Equal(HttpStatusCode.Created, verifyResp.StatusCode);

        var verifyBody = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(verifyBody.TryGetProperty("credential", out var credential));
        Assert.Equal("VerifiableCredential",
            credential.GetProperty("type")[0].GetString());
        Assert.Equal("SsdidRegistrationCredential",
            credential.GetProperty("type")[1].GetString());
        Assert.Equal(clientIdentity.Did,
            credential.GetProperty("credentialSubject").GetProperty("id").GetString());

        // Step 4: Authenticate with the issued VC
        var authResp = await httpClient.PostAsJsonAsync("/api/auth/ssdid/authenticate",
            new { credential }, SnakeJson);
        Assert.Equal(HttpStatusCode.OK, authResp.StatusCode);

        var authBody = await authResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(authBody.TryGetProperty("session_token", out var token));
        Assert.False(string.IsNullOrEmpty(token.GetString()));
        Assert.True(authBody.TryGetProperty("server_did", out _));
        Assert.True(authBody.TryGetProperty("server_signature", out _));
        Assert.True(authBody.TryGetProperty("did", out var returnedDid));
        Assert.Equal(clientIdentity.Did, returnedDid.GetString());
    }

    /// <summary>
    /// Register a DID with the given algorithm, then resolve it back and verify the public key matches.
    /// </summary>
    private static async Task RegisterAndResolve(string algorithmType)
    {
        var cryptoFactory = CreateCryptoFactory();
        var identity = SsdidIdentity.Create(algorithmType, cryptoFactory);

        // Register
        var (registered, registryResponse) = await RegisterDid(identity, cryptoFactory);
        Assert.True(registered, $"DID registration failed for {algorithmType}: {registryResponse}");

        // Resolve
        var encodedDid = Uri.EscapeDataString(identity.Did);
        var resolveResp = await Http.GetAsync($"{RegistryUrl}/api/did/{encodedDid}");
        Assert.Equal(HttpStatusCode.OK, resolveResp.StatusCode);

        var resolvedJson = await resolveResp.Content.ReadFromJsonAsync<JsonElement>();

        // Extract and verify public key
        var extracted = RegistryClient.ExtractPublicKey(resolvedJson, identity.KeyId);
        Assert.NotNull(extracted);

        var (resolvedPubKey, resolvedAlgType) = extracted.Value;
        Assert.Equal(algorithmType, resolvedAlgType);
        Assert.Equal(identity.PublicKey, resolvedPubKey);
    }

    private static async Task<(bool Success, string Response)> RegisterDid(SsdidIdentity identity, CryptoProviderFactory cryptoFactory)
    {
        var didDoc = identity.BuildDidDocument();

        var proofType = CryptoProviderFactory.GetProofType(identity.AlgorithmType);
        var proofOptions = new Dictionary<string, object>
        {
            ["type"] = proofType,
            ["created"] = DateTimeOffset.UtcNow.ToString("o"),
            ["verificationMethod"] = identity.KeyId,
            ["proofPurpose"] = "assertionMethod"
        };

        var payload = SsdidCrypto.W3cSigningPayload(didDoc, proofOptions);
        var proofBytes = identity.SignRaw(payload);
        proofOptions["proofValue"] = SsdidCrypto.MultibaseEncode(proofBytes);

        var reqPayload = new { did_document = didDoc, proof = proofOptions };

        var resp = await Http.PostAsJsonAsync($"{RegistryUrl}/api/did", reqPayload);

        var body = await resp.Content.ReadAsStringAsync();
        return (resp.IsSuccessStatusCode, $"{resp.StatusCode}: {body}");
    }

    // ════════════════════════════════════════════════════════════════════
    // Test Factory: Real Registry (no mock)
    // ════════════════════════════════════════════════════════════════════

    /// <summary>
    /// WebApplicationFactory that uses the REAL SSDID registry.
    /// The RegistryClient's HttpClient is configured to point at the live registry
    /// instead of being intercepted by a mock handler.
    /// </summary>
    private class RealRegistryFactory : Infrastructure.SsdidDriveFactory
    {
        protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);

            builder.ConfigureServices(services =>
            {
                // Configure RegistryClient to point at the real registry
                services.AddHttpClient<RegistryClient>(client =>
                {
                    client.BaseAddress = new Uri(RegistryUrl);
                    client.Timeout = TimeSpan.FromSeconds(10);
                });
            });
        }
    }
}
