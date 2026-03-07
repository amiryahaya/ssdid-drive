using System.Security.Cryptography;

namespace SsdidDrive.Api.Crypto.Providers;

public class EcdsaProvider : ICryptoProvider
{
    public string Family => "Ecdsa";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var curve = GetCurve(variant);
        using var ecdsa = ECDsa.Create(curve);
        var parameters = ecdsa.ExportParameters(true);
        var pubKey = new byte[1 + parameters.Q.X!.Length + parameters.Q.Y!.Length];
        pubKey[0] = 0x04;
        parameters.Q.X.CopyTo(pubKey, 1);
        parameters.Q.Y.CopyTo(pubKey, 1 + parameters.Q.X.Length);
        return (pubKey, parameters.D!);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var curve = GetCurve(variant);
        using var ecdsa = ECDsa.Create();
        ecdsa.ImportParameters(RecoverParameters(curve, privateKey));
        return ecdsa.SignData(message, GetHashAlgorithm(variant));
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var curve = GetCurve(variant);
            var keySize = (publicKey.Length - 1) / 2;
            using var ecdsa = ECDsa.Create();
            var parameters = new ECParameters
            {
                Curve = curve,
                Q = new ECPoint
                {
                    X = publicKey[1..(1 + keySize)],
                    Y = publicKey[(1 + keySize)..]
                }
            };
            ecdsa.ImportParameters(parameters);
            return ecdsa.VerifyData(message, signature, GetHashAlgorithm(variant));
        }
        catch
        {
            return false;
        }
    }

    private static ECCurve GetCurve(string? variant) => variant switch
    {
        "P256" => ECCurve.NamedCurves.nistP256,
        "P384" => ECCurve.NamedCurves.nistP384,
        _ => throw new ArgumentException($"Unsupported ECDSA variant: {variant}")
    };

    private static HashAlgorithmName GetHashAlgorithm(string? variant) => variant switch
    {
        "P256" => HashAlgorithmName.SHA256,
        "P384" => HashAlgorithmName.SHA384,
        _ => HashAlgorithmName.SHA256
    };

    private static ECParameters RecoverParameters(ECCurve curve, byte[] d)
    {
        using var temp = ECDsa.Create(curve);
        var fullParams = temp.ExportParameters(true);
        fullParams.D = d;
        using var keyed = ECDsa.Create();
        keyed.ImportParameters(fullParams);
        return keyed.ExportParameters(true);
    }
}
