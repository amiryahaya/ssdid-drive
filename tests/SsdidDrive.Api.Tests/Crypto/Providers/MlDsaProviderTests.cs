using System.Text;
using Ssdid.Sdk.Server.PqcNist.Providers;
using SsdidDrive.Api.Tests;

namespace SsdidDrive.Api.Tests.Crypto.Providers;

public class MlDsaProviderTests
{
    private readonly MlDsaProvider _provider = new();

    [Fact]
    public void Family_IsMlDsa()
    {
        Assert.Equal("MlDsa", _provider.Family);
    }

    [Theory]
    [InlineData("MlDsa44")]
    [InlineData("MlDsa65")]
    [InlineData("MlDsa87")]
    public void GenerateKeyPair_ProducesNonEmptyKeys(string variant)
    {
        PlatformFacts.SkipIfMlDsaUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);

        Assert.NotNull(publicKey);
        Assert.NotNull(privateKey);
        Assert.NotEmpty(publicKey);
        Assert.NotEmpty(privateKey);
    }

    [Theory]
    [InlineData("MlDsa44")]
    [InlineData("MlDsa65")]
    [InlineData("MlDsa87")]
    public void SignThenVerify_Roundtrip_Succeeds(string variant)
    {
        PlatformFacts.SkipIfMlDsaUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);
        var message = Encoding.UTF8.GetBytes("test message for ML-DSA roundtrip");

        var signature = _provider.Sign(message, privateKey, variant);
        var isValid = _provider.Verify(message, signature, publicKey, variant);

        Assert.True(isValid);
    }

    [Theory]
    [InlineData("MlDsa44")]
    [InlineData("MlDsa65")]
    [InlineData("MlDsa87")]
    public void Verify_WithWrongKey_ReturnsFalse(string variant)
    {
        PlatformFacts.SkipIfMlDsaUnsupported();

        var (_, privateKey) = _provider.GenerateKeyPair(variant);
        var (wrongPublicKey, _) = _provider.GenerateKeyPair(variant);
        var message = Encoding.UTF8.GetBytes("test message for wrong key verification");

        var signature = _provider.Sign(message, privateKey, variant);
        var isValid = _provider.Verify(message, signature, wrongPublicKey, variant);

        Assert.False(isValid);
    }

    [Theory]
    [InlineData("MlDsa44")]
    [InlineData("MlDsa65")]
    [InlineData("MlDsa87")]
    public void Verify_WithTamperedMessage_ReturnsFalse(string variant)
    {
        PlatformFacts.SkipIfMlDsaUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);
        var message = Encoding.UTF8.GetBytes("original message");

        var signature = _provider.Sign(message, privateKey, variant);
        var tamperedMessage = Encoding.UTF8.GetBytes("tampered message");
        var isValid = _provider.Verify(tamperedMessage, signature, publicKey, variant);

        Assert.False(isValid);
    }

    [Fact]
    public void GenerateKeyPair_NullVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair(null));
    }

    [Fact]
    public void GenerateKeyPair_UnsupportedVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair("UnsupportedVariant"));
    }
}
