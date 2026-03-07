using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Ssdid;

public class SsdidIdentityTests
{
    private const string AlgorithmType = "Ed25519VerificationKey2020";

    private static CryptoProviderFactory CreateFactory()
    {
        return new CryptoProviderFactory(new ICryptoProvider[] { new Ed25519Provider() });
    }

    [Fact]
    public void Create_GeneratesIdentity_WithValidDid()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        Assert.StartsWith("did:ssdid:", identity.Did);
    }

    [Fact]
    public void Create_GeneratesIdentity_WithKeyIdEndingInKey1()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        Assert.EndsWith("#key-1", identity.KeyId);
        Assert.StartsWith(identity.Did, identity.KeyId);
    }

    [Fact]
    public void Create_StoresCorrectAlgorithmType()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        Assert.Equal(AlgorithmType, identity.AlgorithmType);
    }

    [Fact]
    public void Create_GeneratesNonEmptyPublicKeyAndPrivateKey()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        Assert.NotNull(identity.PublicKey);
        Assert.NotEmpty(identity.PublicKey);
        Assert.NotNull(identity.PrivateKey);
        Assert.NotEmpty(identity.PrivateKey);
    }

    [Fact]
    public void LoadOrCreate_CreatesNewFile_WhenPathDoesNotExist()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var path = Path.Combine(dir, "identity.json");

        try
        {
            var identity = SsdidIdentity.LoadOrCreate(path, AlgorithmType, CreateFactory());

            Assert.True(File.Exists(path));
            Assert.StartsWith("did:ssdid:", identity.Did);
        }
        finally
        {
            if (Directory.Exists(dir))
                Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void LoadOrCreate_LoadsExistingIdentity_FromFile()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var path = Path.Combine(dir, "identity.json");

        try
        {
            var factory = CreateFactory();
            var created = SsdidIdentity.LoadOrCreate(path, AlgorithmType, factory);
            var loaded = SsdidIdentity.LoadOrCreate(path, AlgorithmType, factory);

            Assert.Equal(created.Did, loaded.Did);
        }
        finally
        {
            if (Directory.Exists(dir))
                Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void LoadOrCreate_PreservesAllProperties_AcrossSaveAndLoad()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var path = Path.Combine(dir, "identity.json");

        try
        {
            var factory = CreateFactory();
            var created = SsdidIdentity.LoadOrCreate(path, AlgorithmType, factory);
            var loaded = SsdidIdentity.LoadOrCreate(path, AlgorithmType, factory);

            Assert.Equal(created.Did, loaded.Did);
            Assert.Equal(created.KeyId, loaded.KeyId);
            Assert.Equal(created.PublicKey, loaded.PublicKey);
            Assert.Equal(created.PrivateKey, loaded.PrivateKey);
        }
        finally
        {
            if (Directory.Exists(dir))
                Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void BuildDidDocument_ReturnsObjectWithCorrectIdAndAlgorithmType()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        var doc = identity.BuildDidDocument();

        // Serialize to JSON and parse to inspect the anonymous object
        var json = JsonSerializer.Serialize(doc);
        using var jsonDoc = JsonDocument.Parse(json);
        var root = jsonDoc.RootElement;

        Assert.Equal(identity.Did, root.GetProperty("id").GetString());

        var verificationMethod = root.GetProperty("verificationMethod")[0];
        Assert.Equal(AlgorithmType, verificationMethod.GetProperty("type").GetString());
        Assert.Equal(identity.KeyId, verificationMethod.GetProperty("id").GetString());
        Assert.Equal(identity.Did, verificationMethod.GetProperty("controller").GetString());
    }

    [Fact]
    public void SignChallenge_ReturnsMultibaseString_StartingWithU()
    {
        var identity = SsdidIdentity.Create(AlgorithmType, CreateFactory());

        var signature = identity.SignChallenge("test-challenge");

        Assert.StartsWith("u", signature);
    }

    [Fact]
    public void SignChallenge_ProducesVerifiableSignature()
    {
        var factory = CreateFactory();
        var identity = SsdidIdentity.Create(AlgorithmType, factory);

        var challenge = "test-challenge";
        var multibaseSig = identity.SignChallenge(challenge);

        var signatureBytes = SsdidCrypto.MultibaseDecode(multibaseSig);
        var messageBytes = Encoding.UTF8.GetBytes(challenge);
        var isValid = factory.Verify(AlgorithmType, messageBytes, signatureBytes, identity.PublicKey);

        Assert.True(isValid);
    }

    [Fact]
    public void SignRaw_ProducesVerifiableSignature()
    {
        var factory = CreateFactory();
        var identity = SsdidIdentity.Create(AlgorithmType, factory);

        var message = Encoding.UTF8.GetBytes("raw-message-data");
        var signature = identity.SignRaw(message);

        var isValid = factory.Verify(AlgorithmType, message, signature, identity.PublicKey);

        Assert.True(isValid);
    }

    [Fact]
    public void SignChallenge_ThrowsInvalidOperationException_WhenCryptoFactoryNotSet()
    {
        var factory = CreateFactory();
        var (pubKey, privKey) = factory.GenerateKeyPair(AlgorithmType);

        var identity = new SsdidIdentity
        {
            Did = "did:ssdid:test",
            KeyId = "did:ssdid:test#key-1",
            PublicKey = pubKey,
            PrivateKey = privKey,
            AlgorithmType = AlgorithmType
        };

        var ex = Assert.Throws<InvalidOperationException>(() => identity.SignChallenge("test"));
        Assert.Contains("CryptoFactory not set", ex.Message);
    }
}
