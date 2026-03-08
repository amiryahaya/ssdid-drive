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
    public void GenerateKeyPair_NullVariant_PublicKeyIsSpkiEncoded()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (publicKey, _) = _provider.GenerateKeyPair(null);

        // SPKI format: SEQUENCE { AlgID(15 bytes) BIT_STRING(2 + 1 + 5 + 54 bytes) } = 79 bytes for Level128
        Assert.Equal(79, publicKey.Length);
        // Starts with ASN.1 SEQUENCE tag
        Assert.Equal(0x30, publicKey[0]);
        // Contains OID 1.3.6.1.4.1.62395.1.1.2 (first OID byte at position 4)
        Assert.Equal(0x06, publicKey[4]); // OID tag
        Assert.Equal(0x0B, publicKey[5]); // OID length = 11
    }

    [Fact]
    public void Sign_ProducesKazWireEncodedSignature()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (_, privateKey) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();

        var signature = _provider.Sign(message, privateKey, null);

        // KazWire sig: 5-byte header + S1(54) + S2(54) + S3(54) = 167 bytes for Level128
        Assert.Equal(167, signature.Length);
        Assert.Equal(0x67, signature[0]); // magic_hi
        Assert.Equal(0x52, signature[1]); // magic_lo
        Assert.Equal(0x01, signature[2]); // alg = SIGN_128
        Assert.Equal(0x10, signature[3]); // type = SIG_DET
        Assert.Equal(0x01, signature[4]); // version
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
        signature[5] ^= 0xFF; // tamper with actual sig data (skip 5-byte KazWire header)
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
        // SPKI: 79 bytes for Level128 (with KazWire header)
        Assert.Equal(79, publicKey.Length);
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

    [Fact]
    public void CrossPlatformInterop_DumpsTestVectors()
    {
        PlatformFacts.SkipIfKazSignUnsupported();

        var (spkiPk, sk) = _provider.GenerateKeyPair(null);
        var message = "hello world"u8.ToArray();
        var kazWireSig = _provider.Sign(message, sk, null);

        // Verify locally
        Assert.True(_provider.Verify(message, kazWireSig, spkiPk, null));

        // Dump test vectors for Java interop
        Console.WriteLine($"SPKI_HEX={Convert.ToHexString(spkiPk)}");
        Console.WriteLine($"SIG_HEX={Convert.ToHexString(kazWireSig)}");
        Console.WriteLine($"MSG_HEX={Convert.ToHexString(message)}");

        // Save binary files for Java test
        var tmpDir = Path.GetTempPath();
        File.WriteAllBytes(Path.Combine(tmpDir, "kaz_spki.bin"), spkiPk);
        File.WriteAllBytes(Path.Combine(tmpDir, "kaz_sig.bin"), kazWireSig);
        File.WriteAllBytes(Path.Combine(tmpDir, "kaz_msg.bin"), message);

        Console.WriteLine($"Test vectors saved to {tmpDir}kaz_*.bin");
    }
}
