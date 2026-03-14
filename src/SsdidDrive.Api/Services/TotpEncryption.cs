using System.Security.Cryptography;

namespace SsdidDrive.Api.Services;

public class TotpEncryption
{
    private readonly byte[] _key;

    public TotpEncryption(IConfiguration config)
    {
        var keyBase64 = config["Auth:TotpEncryptionKey"];
        if (string.IsNullOrEmpty(keyBase64))
        {
            // Generate a key for development — log warning
            _key = RandomNumberGenerator.GetBytes(32);
        }
        else
        {
            _key = Convert.FromBase64String(keyBase64);
        }

        if (_key.Length != 32)
            throw new ArgumentException("Auth:TotpEncryptionKey must be 32 bytes (base64-encoded)");
    }

    public string Encrypt(string plaintext)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var plaintextBytes = System.Text.Encoding.UTF8.GetBytes(plaintext);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[16];

        using var aes = new AesGcm(_key, 16);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        // Format: base64(nonce + ciphertext + tag)
        var combined = new byte[nonce.Length + ciphertext.Length + tag.Length];
        Buffer.BlockCopy(nonce, 0, combined, 0, nonce.Length);
        Buffer.BlockCopy(ciphertext, 0, combined, nonce.Length, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, combined, nonce.Length + ciphertext.Length, tag.Length);

        return Convert.ToBase64String(combined);
    }

    public string Decrypt(string encrypted)
    {
        var combined = Convert.FromBase64String(encrypted);

        var nonce = combined[..12];
        var tag = combined[^16..];
        var ciphertext = combined[12..^16];
        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_key, 16);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return System.Text.Encoding.UTF8.GetString(plaintext);
    }
}
