using SsdidDrive.Api.Crypto.Providers;

namespace SsdidDrive.Api.Tests.Crypto.Providers;

public class Ed25519ProviderTests
{
    private readonly Ed25519Provider _provider = new();

    [Fact]
    public void Family_IsEd25519()
    {
        Assert.Equal("Ed25519", _provider.Family);
    }

    [Fact]
    public void GenerateKeyPair_Returns32ByteKeys()
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair();

        Assert.Equal(32, publicKey.Length);
        Assert.Equal(32, privateKey.Length);
    }

    [Fact]
    public void Sign_Produces64ByteSignature()
    {
        var (_, privateKey) = _provider.GenerateKeyPair();
        var message = "hello"u8.ToArray();

        var signature = _provider.Sign(message, privateKey);

        Assert.Equal(64, signature.Length);
    }

    [Fact]
    public void SignThenVerify_Roundtrip_Succeeds()
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair();
        var message = "test message"u8.ToArray();

        var signature = _provider.Sign(message, privateKey);
        var result = _provider.Verify(message, signature, publicKey);

        Assert.True(result);
    }

    [Fact]
    public void Verify_WithWrongPublicKey_ReturnsFalse()
    {
        var (_, privateKey) = _provider.GenerateKeyPair();
        var (wrongPublicKey, _) = _provider.GenerateKeyPair();
        var message = "test message"u8.ToArray();

        var signature = _provider.Sign(message, privateKey);
        var result = _provider.Verify(message, signature, wrongPublicKey);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WithTamperedMessage_ReturnsFalse()
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair();
        var message = "original"u8.ToArray();

        var signature = _provider.Sign(message, privateKey);
        var tampered = "tampered"u8.ToArray();
        var result = _provider.Verify(tampered, signature, publicKey);

        Assert.False(result);
    }

    [Fact]
    public void Verify_WithTamperedSignature_ReturnsFalse()
    {
        var (publicKey, privateKey) = _provider.GenerateKeyPair();
        var message = "test message"u8.ToArray();

        var signature = _provider.Sign(message, privateKey);
        signature[0] ^= 0xFF;
        var result = _provider.Verify(message, signature, publicKey);

        Assert.False(result);
    }
}
