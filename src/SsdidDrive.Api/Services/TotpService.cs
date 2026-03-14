using System.Security.Cryptography;
using System.Text.Json;
using OtpNet;

namespace SsdidDrive.Api.Services;

public class TotpService
{
    private const string Issuer = "SSDID Drive";
    private const int SecretLength = 20;
    private const int BackupCodeCount = 10;
    private const int BackupCodeLength = 8;

    public string GenerateSecret()
    {
        var secret = new byte[SecretLength];
        RandomNumberGenerator.Fill(secret);
        return Base32Encoding.ToString(secret);
    }

    public string GenerateOtpAuthUri(string base32Secret, string email)
    {
        var encodedIssuer = Uri.EscapeDataString(Issuer);
        var encodedEmail = Uri.EscapeDataString(email);
        var label = $"{encodedIssuer}:{encodedEmail}";
        return $"otpauth://totp/{label}?secret={base32Secret}&issuer={encodedIssuer}&algorithm=SHA1&digits=6&period=30";
    }

    public bool VerifyCode(string base32Secret, string code)
    {
        var secretBytes = Base32Encoding.ToBytes(base32Secret);
        var totp = new Totp(secretBytes);
        return totp.VerifyTotp(code, out _, new VerificationWindow(previous: 1, future: 1));
    }

    public List<string> GenerateBackupCodes()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var codes = new List<string>(BackupCodeCount);
        for (int i = 0; i < BackupCodeCount; i++)
        {
            var code = new char[BackupCodeLength];
            for (int j = 0; j < BackupCodeLength; j++)
                code[j] = chars[RandomNumberGenerator.GetInt32(chars.Length)];
            codes.Add(new string(code));
        }
        return codes;
    }

    public (bool Valid, string? RemainingCodesJson) VerifyBackupCode(string codesJson, string code)
    {
        var codes = JsonSerializer.Deserialize<List<string>>(codesJson);
        if (codes is null) return (false, null);
        var match = codes.FirstOrDefault(c =>
            string.Equals(c, code, StringComparison.OrdinalIgnoreCase));
        if (match is null) return (false, null);
        codes.Remove(match);
        return (true, JsonSerializer.Serialize(codes));
    }
}
