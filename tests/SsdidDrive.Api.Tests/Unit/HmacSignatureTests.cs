using System.Security.Cryptography;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Tests.Unit;

public class HmacSignatureTests
{
    [Fact]
    public void ComputeSignature_ReturnsConsistentResult()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("{\"name\":\"test\"}");

        var sig1 = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);
        var sig2 = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);

        Assert.Equal(sig1, sig2);
    }

    [Fact]
    public void ComputeSignature_DifferentSecrets_ProduceDifferentSignatures()
    {
        var secret1 = RandomNumberGenerator.GetBytes(32);
        var secret2 = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "GET";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var sig1 = HmacSignatureHelper.ComputeSignature(secret1, timestamp, method, path, bodyHash);
        var sig2 = HmacSignatureHelper.ComputeSignature(secret2, timestamp, method, path, bodyHash);

        Assert.NotEqual(sig1, sig2);
    }

    [Fact]
    public void ComputeBodyHash_EmptyBody_ReturnsExpectedHash()
    {
        var hash = HmacSignatureHelper.ComputeBodyHash("");
        Assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", hash);
    }

    [Fact]
    public void VerifySignature_ValidSignature_ReturnsTrue()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("{\"data\":\"test\"}");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);

        Assert.True(HmacSignatureHelper.VerifySignature(secret, timestamp, method, path, bodyHash, signature));
    }

    [Fact]
    public void VerifySignature_TamperedSignature_ReturnsFalse()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("data");

        HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);
        var tampered = Convert.ToBase64String(new byte[32]);

        Assert.False(HmacSignatureHelper.VerifySignature(secret, timestamp, method, path, bodyHash, tampered));
    }

    [Fact]
    public void VerifySignature_DifferentPath_ReturnsFalse()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "GET";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, "/api/ext/files", bodyHash);

        Assert.False(HmacSignatureHelper.VerifySignature(secret, timestamp, method, "/api/ext/folders", bodyHash, signature));
    }
}
