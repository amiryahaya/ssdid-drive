using Ssdid.Sdk.Server.Encoding;

namespace SsdidDrive.Api.Tests.Ssdid;

public class SsdidCryptoTests
{
    [Fact]
    public void GenerateChallenge_ReturnsNonNullNonEmptyString()
    {
        var challenge = SsdidEncoding.GenerateChallenge();

        Assert.NotNull(challenge);
        Assert.NotEmpty(challenge);
    }

    [Fact]
    public void GenerateChallenge_ReturnsDifferentValuesEachCall()
    {
        var challenge1 = SsdidEncoding.GenerateChallenge();
        var challenge2 = SsdidEncoding.GenerateChallenge();

        Assert.NotEqual(challenge1, challenge2);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(16)]
    [InlineData(32)]
    public void Base64UrlEncode_Decode_Roundtrip(int length)
    {
        var data = new byte[length];
        for (var i = 0; i < length; i++)
            data[i] = (byte)(i * 7 + 3);

        var encoded = SsdidEncoding.Base64UrlEncode(data);
        var decoded = SsdidEncoding.Base64UrlDecode(encoded);

        Assert.Equal(data, decoded);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(16)]
    [InlineData(32)]
    public void Base64UrlEncode_ProducesNoForbiddenCharacters(int length)
    {
        var data = new byte[length];
        for (var i = 0; i < length; i++)
            data[i] = (byte)(i * 13 + 5);

        var encoded = SsdidEncoding.Base64UrlEncode(data);

        Assert.DoesNotContain("+", encoded);
        Assert.DoesNotContain("/", encoded);
        Assert.DoesNotContain("=", encoded);
    }

    [Fact]
    public void Base64UrlDecode_HandlesPaddingCase_LengthMod4_Is0()
    {
        // 3 bytes -> 4 base64 chars -> length % 4 == 0
        var data = new byte[] { 0xAA, 0xBB, 0xCC };
        var encoded = SsdidEncoding.Base64UrlEncode(data);

        Assert.Equal(0, encoded.Length % 4);

        var decoded = SsdidEncoding.Base64UrlDecode(encoded);
        Assert.Equal(data, decoded);
    }

    [Fact]
    public void Base64UrlDecode_HandlesPaddingCase_LengthMod4_Is2()
    {
        // 1 byte -> 2 base64 chars (after trimming '==') -> length % 4 == 2
        var data = new byte[] { 0xFF };
        var encoded = SsdidEncoding.Base64UrlEncode(data);

        Assert.Equal(2, encoded.Length % 4);

        var decoded = SsdidEncoding.Base64UrlDecode(encoded);
        Assert.Equal(data, decoded);
    }

    [Fact]
    public void Base64UrlDecode_HandlesPaddingCase_LengthMod4_Is3()
    {
        // 2 bytes -> 3 base64 chars (after trimming '=') -> length % 4 == 3
        var data = new byte[] { 0xAA, 0xBB };
        var encoded = SsdidEncoding.Base64UrlEncode(data);

        Assert.Equal(3, encoded.Length % 4);

        var decoded = SsdidEncoding.Base64UrlDecode(encoded);
        Assert.Equal(data, decoded);
    }

    [Fact]
    public void MultibaseEncode_StartsWithUPrefix()
    {
        var data = new byte[] { 1, 2, 3 };

        var encoded = SsdidEncoding.MultibaseEncode(data);

        Assert.StartsWith("u", encoded);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(16)]
    [InlineData(32)]
    public void MultibaseEncode_Decode_Roundtrip(int length)
    {
        var data = new byte[length];
        for (var i = 0; i < length; i++)
            data[i] = (byte)(i * 11 + 7);

        var encoded = SsdidEncoding.MultibaseEncode(data);
        var decoded = SsdidEncoding.MultibaseDecode(encoded);

        Assert.Equal(data, decoded);
    }

    [Fact]
    public void MultibaseDecode_InvalidPrefix_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => SsdidEncoding.MultibaseDecode("zSGVsbG8"));
    }

    [Fact]
    public void MultibaseDecode_EmptyString_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => SsdidEncoding.MultibaseDecode(""));
    }
}
