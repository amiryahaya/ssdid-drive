using System.Security.Cryptography;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Encoding utilities for SSDID: Base64url, multibase, challenge generation.
/// </summary>
public static class SsdidCrypto
{
    public static string GenerateChallenge()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64UrlEncode(bytes);
    }

    public static string Base64UrlEncode(byte[] data)
    {
        return Convert.ToBase64String(data)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }

    public static byte[] Base64UrlDecode(string input)
    {
        var s = input.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }

    public static string MultibaseEncode(byte[] data) => "u" + Base64UrlEncode(data);

    public static byte[] MultibaseDecode(string multibase)
    {
        if (string.IsNullOrEmpty(multibase) || multibase[0] != 'u')
            throw new ArgumentException("Invalid multibase encoding (expected 'u' prefix)");

        return Base64UrlDecode(multibase[1..]);
    }
}
