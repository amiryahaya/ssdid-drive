using System.Text;
using Ssdid.Sdk.Server.PqcNist.Providers;
using SsdidDrive.Api.Tests;

namespace SsdidDrive.Api.Tests.Crypto.Providers;

public class SlhDsaProviderTests
{
    private readonly SlhDsaProvider _provider = new();

    [Fact]
    public void Family_IsSlhDsa()
    {
        Assert.Equal("SlhDsa", _provider.Family);
    }

    [Theory]
    [InlineData("Sha2_128f")]
    [InlineData("Shake_128f")]
    [InlineData("Sha2_256f")]
    public void GenerateKeyPair_ProducesNonEmptyKeys(string variant)
    {
        PlatformFacts.SkipIfSlhDsaUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);

        Assert.NotNull(publicKey);
        Assert.NotNull(privateKey);
        Assert.NotEmpty(publicKey);
        Assert.NotEmpty(privateKey);
    }

    [Theory]
    [InlineData("Sha2_128f")]
    [InlineData("Shake_128f")]
    [InlineData("Sha2_256f")]
    public void SignThenVerify_Roundtrip_Succeeds(string variant)
    {
        PlatformFacts.SkipIfSlhDsaUnsupported();

        var (publicKey, privateKey) = _provider.GenerateKeyPair(variant);
        var message = Encoding.UTF8.GetBytes("test message for SLH-DSA roundtrip");

        var signature = _provider.Sign(message, privateKey, variant);
        var isValid = _provider.Verify(message, signature, publicKey, variant);

        Assert.True(isValid);
    }

    [Theory]
    [InlineData("Sha2_128f")]
    [InlineData("Shake_128f")]
    [InlineData("Sha2_256f")]
    public void Verify_WithWrongKey_ReturnsFalse(string variant)
    {
        PlatformFacts.SkipIfSlhDsaUnsupported();

        var (_, privateKey) = _provider.GenerateKeyPair(variant);
        var (wrongPublicKey, _) = _provider.GenerateKeyPair(variant);
        var message = Encoding.UTF8.GetBytes("test message for wrong key verification");

        var signature = _provider.Sign(message, privateKey, variant);
        var isValid = _provider.Verify(message, signature, wrongPublicKey, variant);

        Assert.False(isValid);
    }

    [Fact]
    public void GenerateKeyPair_UnsupportedVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair("UnsupportedVariant"));
    }

    [Fact]
    public void GenerateKeyPair_NullVariant_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _provider.GenerateKeyPair(null));
    }
}
