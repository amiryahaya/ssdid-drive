using System.Security.Cryptography;

namespace SsdidDrive.Api.Crypto.Providers;

public class SlhDsaProvider : ICryptoProvider
{
    public string Family => "SlhDsa";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var algorithm = GetAlgorithm(variant);
        using var slhDsa = SlhDsa.GenerateKey(algorithm);
        var pubKey = slhDsa.ExportSlhDsaPublicKey();
        var privKey = slhDsa.ExportSlhDsaPrivateKey();
        return (pubKey, privKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var algorithm = GetAlgorithm(variant);
        using var slhDsa = SlhDsa.ImportSlhDsaPrivateKey(algorithm, privateKey);
        var signature = new byte[algorithm.SignatureSizeInBytes];
        slhDsa.SignData(message, signature);
        return signature;
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var algorithm = GetAlgorithm(variant);
            using var slhDsa = SlhDsa.ImportSlhDsaPublicKey(algorithm, publicKey);
            return slhDsa.VerifyData(message, signature);
        }
        catch
        {
            return false;
        }
    }

    private static SlhDsaAlgorithm GetAlgorithm(string? variant) => variant switch
    {
        "Sha2_128s" => SlhDsaAlgorithm.SlhDsaSha2_128s,
        "Sha2_128f" => SlhDsaAlgorithm.SlhDsaSha2_128f,
        "Sha2_192s" => SlhDsaAlgorithm.SlhDsaSha2_192s,
        "Sha2_192f" => SlhDsaAlgorithm.SlhDsaSha2_192f,
        "Sha2_256s" => SlhDsaAlgorithm.SlhDsaSha2_256s,
        "Sha2_256f" => SlhDsaAlgorithm.SlhDsaSha2_256f,
        "Shake_128s" => SlhDsaAlgorithm.SlhDsaShake128s,
        "Shake_128f" => SlhDsaAlgorithm.SlhDsaShake128f,
        "Shake_192s" => SlhDsaAlgorithm.SlhDsaShake192s,
        "Shake_192f" => SlhDsaAlgorithm.SlhDsaShake192f,
        "Shake_256s" => SlhDsaAlgorithm.SlhDsaShake256s,
        "Shake_256f" => SlhDsaAlgorithm.SlhDsaShake256f,
        _ => throw new ArgumentException($"Unsupported SLH-DSA variant: {variant}")
    };
}
