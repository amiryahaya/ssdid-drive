using Ssdid.Sdk.Server.Crypto.Providers;

namespace SsdidDrive.Api.Tests.Crypto.Providers;

public class EcdsaProviderTests
{
    private readonly EcdsaProvider _provider = new();

    [Fact]
    public void Family_IsEcdsa()
    {
        Assert.Equal("Ecdsa", _provider.Family);
    }

    [Theory]
    [InlineData("P256", 65)]
    [InlineData("P384", 97)]
    public void GenerateKeyPair_ReturnsUncompressedPublicKey(string variant, int expectedPubKeyLength)
    {
        var (publicKey, _) = _provider.GenerateKeyPair(variant);

        Assert.Equal(expectedPubKeyLength, publicKey.Length);
        Assert.Equal(0x04, publicKey[0]);
    }

    [Theory]
    [InlineData("P256")]
    [InlineData("P384")]
    public void SignThenVerify_Roundtrip_Succeeds(string variant)
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);
        var message = "test message"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, variant);
        var result = _provider.Verify(message, signature, publicKey, variant);

        Assert.True(result);
    }

    [Theory]
    [InlineData("P256")]
    [InlineData("P384")]
    public void Verify_WithWrongKey_ReturnsFalse(string variant)
    {
        var (_, privateKey) = _provider.GenerateKeyPair(variant);
        var (wrongPublicKey, _) = _provider.GenerateKeyPair(variant);
        var message = "test message"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, variant);
        var result = _provider.Verify(message, signature, wrongPublicKey, variant);

        Assert.False(result);
    }

    [Theory]
    [InlineData("P256")]
    [InlineData("P384")]
    public void Verify_WithTamperedMessage_ReturnsFalse(string variant)
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);
        var message = "original"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, variant);
        var tampered = "tampered"u8.ToArray();
        var result = _provider.Verify(tampered, signature, publicKey, variant);

        Assert.False(result);
    }

    [Fact]
    public void GenerateKeyPair_WithNullVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair(null));
    }

    [Fact]
    public void GenerateKeyPair_WithUnsupportedVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair("P521"));
    }
}
