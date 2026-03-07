using System.Security.Cryptography;

namespace SsdidDrive.Api.Crypto.Providers;

public class MlDsaProvider : ICryptoProvider
{
    public string Family => "MlDsa";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var algorithm = GetAlgorithm(variant);
        using var mlDsa = MLDsa.GenerateKey(algorithm);
        var pubKey = mlDsa.ExportMLDsaPublicKey();
        var privKey = mlDsa.ExportMLDsaPrivateKey();
        return (pubKey, privKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var algorithm = GetAlgorithm(variant);
        using var mlDsa = MLDsa.ImportMLDsaPrivateKey(algorithm, privateKey);
        var signature = new byte[algorithm.SignatureSizeInBytes];
        mlDsa.SignData(message, signature);
        return signature;
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var algorithm = GetAlgorithm(variant);
            using var mlDsa = MLDsa.ImportMLDsaPublicKey(algorithm, publicKey);
            return mlDsa.VerifyData(message, signature);
        }
        catch
        {
            return false;
        }
    }

    private static MLDsaAlgorithm GetAlgorithm(string? variant) => variant switch
    {
        "MlDsa44" => MLDsaAlgorithm.MLDsa44,
        "MlDsa65" => MLDsaAlgorithm.MLDsa65,
        "MlDsa87" => MLDsaAlgorithm.MLDsa87,
        _ => throw new ArgumentException($"Unsupported ML-DSA variant: {variant}")
    };
}
