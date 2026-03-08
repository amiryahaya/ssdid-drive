using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Integration;

/// <summary>
/// Integration tests that hit the real SSDID registry (https://registry.ssdid.my).
/// These test the actual server ↔ registry communication path for all algorithms:
/// Ed25519, ML-DSA (FIPS 204), SLH-DSA (FIPS 205), and KAZ-Sign.
///
/// KAZ-Sign registry tests are skipped because the C native library (v3.0) and
/// Java JCA provider (kaz-pqc-jcajce v0.0.2) use incompatible signature formats:
///   C library:  S1(54) + S2(54) + S3(54) = 162 bytes (raw concatenation)
///   Java JCA:   s1(49) + s2(8) = 57 bytes (KazWire encoding with 5-byte header)
/// Local KAZ-Sign sign/verify works (C↔C), but registry verification fails (C→Java).
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

    // ── Test 1: Register DID with real registry (Ed25519) ──

    [Fact]
    public async Task RegisterDid_Ed25519_Succeeds()
    {
        SkipIfRegistryUnavailable();
        await RegisterAndResolve("Ed25519VerificationKey2020");
    }

    // ── Tests 2-5: PQC algorithms ──

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
        // Skip: C native library signatures (S1||S2||S3 = 162 bytes) are incompatible
        // with registry's Java JCA KazWire format (s1+s2 = 57 bytes + 5-byte header).
        // Requires aligning C and Java KAZ-Sign implementations.
        Assert.Skip("KAZ-Sign C↔Java signature format incompatibility");

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

        // Extract public key from resolved DID Document
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
        Assert.Equal(54, identity.PublicKey.Length);
        Assert.Equal(32, identity.PrivateKey.Length);
        Assert.Equal(162, proofBytes.Length);
    }

    // ── Shared helpers ──

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
}
