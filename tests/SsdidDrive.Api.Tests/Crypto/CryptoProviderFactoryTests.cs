using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Tests.Crypto;

public class FakeCryptoProvider : ICryptoProvider
{
    public string Family { get; }

    public string? LastVariant { get; private set; }
    public byte[]? LastMessage { get; private set; }
    public byte[]? LastPrivateKey { get; private set; }
    public byte[]? LastPublicKey { get; private set; }
    public byte[]? LastSignature { get; private set; }

    public bool VerifyResult { get; set; } = true;

    public FakeCryptoProvider(string family)
    {
        Family = family;
    }

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        LastVariant = variant;
        return (new byte[] { 0xAA, 0xBB }, new byte[] { 0xCC, 0xDD });
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        LastMessage = message;
        LastPrivateKey = privateKey;
        LastVariant = variant;
        return new byte[] { 0x51, 0x69 };
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        LastMessage = message;
        LastSignature = signature;
        LastPublicKey = publicKey;
        LastVariant = variant;
        return VerifyResult;
    }
}

public class CryptoProviderFactoryTests
{
    private readonly FakeCryptoProvider _ed25519Provider = new("Ed25519");
    private readonly FakeCryptoProvider _ecdsaProvider = new("Ecdsa");

    private CryptoProviderFactory CreateFactory(params ICryptoProvider[] providers)
    {
        return new CryptoProviderFactory(providers);
    }

    private CryptoProviderFactory CreateDefaultFactory()
    {
        return CreateFactory(_ed25519Provider, _ecdsaProvider);
    }

    [Fact]
    public void Resolve_Ed25519VerificationKey2020_ReturnsCorrectProvider()
    {
        var factory = CreateDefaultFactory();

        var (provider, variant) = factory.Resolve("Ed25519VerificationKey2020");

        Assert.Same(_ed25519Provider, provider);
        Assert.Null(variant);
    }

    [Fact]
    public void Resolve_EcdsaSecp256r1VerificationKey2019_ReturnsCorrectVariant()
    {
        var factory = CreateDefaultFactory();

        var (provider, variant) = factory.Resolve("EcdsaSecp256r1VerificationKey2019");

        Assert.Same(_ecdsaProvider, provider);
        Assert.Equal("P256", variant);
    }

    [Fact]
    public void Resolve_UnsupportedVmType_ThrowsArgumentException()
    {
        var factory = CreateDefaultFactory();

        var ex = Assert.Throws<ArgumentException>(() => factory.Resolve("UnsupportedType"));
        Assert.Contains("Unsupported verification method type", ex.Message);
    }

    [Fact]
    public void Resolve_ProviderFamilyNotRegistered_ThrowsInvalidOperationException()
    {
        // Create factory without an Ed25519 provider, then try to resolve Ed25519
        var factory = CreateFactory(_ecdsaProvider);

        var ex = Assert.Throws<InvalidOperationException>(
            () => factory.Resolve("Ed25519VerificationKey2020"));
        Assert.Contains("No crypto provider registered for family", ex.Message);
    }

    [Fact]
    public void Sign_DispatchesToCorrectProvider()
    {
        var factory = CreateDefaultFactory();
        var message = new byte[] { 0x01, 0x02 };
        var privateKey = new byte[] { 0x03, 0x04 };

        var signature = factory.Sign("Ed25519VerificationKey2020", message, privateKey);

        Assert.Equal(new byte[] { 0x51, 0x69 }, signature);
        Assert.Same(message, _ed25519Provider.LastMessage);
        Assert.Same(privateKey, _ed25519Provider.LastPrivateKey);
        Assert.Null(_ed25519Provider.LastVariant);
    }

    [Fact]
    public void Verify_DispatchesToCorrectProvider()
    {
        var factory = CreateDefaultFactory();
        var message = new byte[] { 0x01, 0x02 };
        var signature = new byte[] { 0x03, 0x04 };
        var publicKey = new byte[] { 0x05, 0x06 };
        _ecdsaProvider.VerifyResult = true;

        var result = factory.Verify(
            "EcdsaSecp256r1VerificationKey2019", message, signature, publicKey);

        Assert.True(result);
        Assert.Same(message, _ecdsaProvider.LastMessage);
        Assert.Same(signature, _ecdsaProvider.LastSignature);
        Assert.Same(publicKey, _ecdsaProvider.LastPublicKey);
        Assert.Equal("P256", _ecdsaProvider.LastVariant);
    }

    [Fact]
    public void GenerateKeyPair_DispatchesToCorrectProvider()
    {
        var factory = CreateDefaultFactory();

        var (publicKey, privateKey) = factory.GenerateKeyPair("EcdsaSecp256r1VerificationKey2019");

        Assert.Equal(new byte[] { 0xAA, 0xBB }, publicKey);
        Assert.Equal(new byte[] { 0xCC, 0xDD }, privateKey);
        Assert.Equal("P256", _ecdsaProvider.LastVariant);
    }

    [Fact]
    public void GetProofType_ReturnsCorrectProofType()
    {
        var proofType = CryptoProviderFactory.GetProofType("Ed25519VerificationKey2020");

        Assert.Equal("Ed25519Signature2020", proofType);
    }

    [Fact]
    public void GetProofType_UnsupportedVmType_ThrowsArgumentException()
    {
        var ex = Assert.Throws<ArgumentException>(
            () => CryptoProviderFactory.GetProofType("UnsupportedType"));
        Assert.Contains("No proof type mapped for", ex.Message);
    }
}
