using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Tests;

namespace SsdidDrive.Api.Tests.Crypto.Providers;

public class KazSignProviderTests : IDisposable
{
    private readonly KazSignProvider _provider = new();

    public void Dispose() => _provider.Dispose();

    [Fact]
    public void Family_ReturnsKazSign()
    {
        Assert.Equal("KazSign", _provider.Family);
    }

    [Fact]
    public void GenerateKeyPair_NullVariant_ProducesNonEmptyKeys()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(null);

        Assert.NotNull(publicKey);
        Assert.NotNull(privateKey);
        Assert.NotEmpty(publicKey);
        Assert.NotEmpty(privateKey);
    }

    [Fact]
    public void GenerateKeyPair_NullVariant_PublicKeyIs54Bytes()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, _) = _provider.GenerateKeyPair(null);

        Assert.Equal(54, publicKey.Length);
    }

    [Fact]
    public void Sign_Verify_Roundtrip_Succeeds()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, null);
        var result = _provider.Verify(message, signature, publicKey, null);

        Assert.True(result);
    }

    [Fact]
    public void Verify_WithWrongKey_ReturnsFalse()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (_, privateKey) = _provider.GenerateKeyPair(null);
        var (wrongPublicKey, _) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, null);
        var result = _provider.Verify(message, signature, wrongPublicKey, null);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WithTamperedMessage_ReturnsFalse()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, null);
        var tampered = "tampered msg"u8.ToArray();
        var result = _provider.Verify(tampered, signature, publicKey, null);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WithTamperedSignature_ReturnsFalse()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, null);
        signature[0] ^= 0xFF;
        var result = _provider.Verify(message, signature, publicKey, null);

        Assert.False(result);
    }

    [Fact]
    public void GenerateKeyPair_Variant128_Works()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair("128");

        Assert.NotEmpty(publicKey);
        Assert.NotEmpty(privateKey);
        Assert.Equal(54, publicKey.Length);
    }

    [Fact]
    public void GenerateKeyPair_UnsupportedVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair("unsupported"));
    }

    [Fact]
    public void Dispose_DoesNotThrow()
    {
        var provider = new KazSignProvider();
        var exception = Record.Exception(() => provider.Dispose());

        Assert.Null(exception);
    }

    [Fact]
    public void ImplementsIDisposable()
    {
        Assert.IsAssignableFrom<IDisposable>(_provider);
    }
}
