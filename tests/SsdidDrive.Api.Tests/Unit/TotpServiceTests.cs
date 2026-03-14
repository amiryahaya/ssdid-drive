using OtpNet;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class TotpServiceTests
{
    private readonly TotpService _sut = new();

    [Fact]
    public void GenerateSecret_Returns20ByteBase32String()
    {
        var secret = _sut.GenerateSecret();
        var decoded = Base32Encoding.ToBytes(secret);
        Assert.Equal(20, decoded.Length);
    }

    [Fact]
    public void GenerateOtpAuthUri_ReturnsValidUri()
    {
        var secret = _sut.GenerateSecret();
        var uri = _sut.GenerateOtpAuthUri(secret, "test@example.com");
        Assert.StartsWith("otpauth://totp/SSDID%20Drive:test%40example.com", uri);
        Assert.Contains($"secret={secret}", uri);
        Assert.Contains("issuer=SSDID%20Drive", uri);
    }

    [Fact]
    public void VerifyCode_CurrentCode_ReturnsTrue()
    {
        var secret = _sut.GenerateSecret();
        var totp = new Totp(Base32Encoding.ToBytes(secret));
        var code = totp.ComputeTotp();
        Assert.True(_sut.VerifyCode(secret, code));
    }

    [Fact]
    public void VerifyCode_WrongCode_ReturnsFalse()
    {
        var secret = _sut.GenerateSecret();
        Assert.False(_sut.VerifyCode(secret, "000000"));
    }

    [Fact]
    public void GenerateBackupCodes_Returns10UniqueCodes()
    {
        var codes = _sut.GenerateBackupCodes();
        Assert.Equal(10, codes.Count);
        Assert.Equal(10, codes.Distinct().Count());
        Assert.All(codes, c =>
        {
            Assert.Equal(8, c.Length);
            Assert.True(c.All(char.IsLetterOrDigit));
        });
    }

    [Fact]
    public void VerifyBackupCode_ValidCode_ReturnsTrueAndRemovesCode()
    {
        var codes = _sut.GenerateBackupCodes();
        var codeToUse = codes[0];
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);
        var (valid, remainingJson) = _sut.VerifyBackupCode(codesJson, codeToUse);
        Assert.True(valid);
        var remaining = System.Text.Json.JsonSerializer.Deserialize<List<string>>(remainingJson!);
        Assert.Equal(9, remaining!.Count);
        Assert.DoesNotContain(codeToUse, remaining);
    }

    [Fact]
    public void VerifyBackupCode_InvalidCode_ReturnsFalse()
    {
        var codes = _sut.GenerateBackupCodes();
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);
        var (valid, _) = _sut.VerifyBackupCode(codesJson, "INVALID1");
        Assert.False(valid);
    }

    [Fact]
    public void VerifyBackupCode_CaseInsensitive()
    {
        var codes = _sut.GenerateBackupCodes();
        var codeToUse = codes[0].ToLowerInvariant();
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);
        var (valid, _) = _sut.VerifyBackupCode(codesJson, codeToUse);
        Assert.True(valid);
    }
}
