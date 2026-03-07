using Antrapol.Kaz.Sign;

namespace SsdidDrive.Api.Crypto.Providers;

public class KazSignProvider : ICryptoProvider, IDisposable
{
    public string Family => "KazSign";

    private const SecurityLevel DefaultLevel = SecurityLevel.Level128;

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        signer.GenerateKeyPair(out var publicKey, out var secretKey);
        return (publicKey, secretKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        return signer.SignDetached(message, privateKey);
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var level = InferLevelFromPublicKey(publicKey);
            using var signer = new KazSigner(level);
            return signer.VerifyDetached(message, signature, publicKey);
        }
        catch
        {
            return false;
        }
    }

    private static SecurityLevel ParseLevel(string? variant) => variant switch
    {
        "128" => SecurityLevel.Level128,
        "192" => SecurityLevel.Level192,
        "256" => SecurityLevel.Level256,
        null => DefaultLevel,
        _ => throw new ArgumentException($"Unsupported KAZ-Sign variant: {variant}")
    };

    private static SecurityLevel InferLevelFromPublicKey(byte[] publicKey) => publicKey.Length switch
    {
        54 => SecurityLevel.Level128,
        88 => SecurityLevel.Level192,
        119 => SecurityLevel.Level256,
        _ => throw new ArgumentException($"Cannot infer KAZ-Sign level from public key size: {publicKey.Length}")
    };

    public void Dispose() { }
}
