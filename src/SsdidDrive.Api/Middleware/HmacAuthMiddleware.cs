using System.Security.Cryptography;
using System.Text;

namespace SsdidDrive.Api.Middleware;

public static class HmacSignatureHelper
{
    public static string ComputeBodyHash(string body)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(body));
        return Convert.ToHexStringLower(hash);
    }

    public static string ComputeSignature(byte[] secret, string timestamp, string method, string path, string bodyHash)
    {
        var stringToSign = $"{timestamp}\n{method}\n{path}\n{bodyHash}";
        var signatureBytes = HMACSHA256.HashData(secret, Encoding.UTF8.GetBytes(stringToSign));
        return Convert.ToBase64String(signatureBytes);
    }

    public static bool VerifySignature(byte[] secret, string timestamp, string method, string path, string bodyHash, string providedSignature)
    {
        var expected = ComputeSignature(secret, timestamp, method, path, bodyHash);
        var expectedBytes = Convert.FromBase64String(expected);
        var providedBytes = Convert.FromBase64String(providedSignature);
        return CryptographicOperations.FixedTimeEquals(expectedBytes, providedBytes);
    }
}
