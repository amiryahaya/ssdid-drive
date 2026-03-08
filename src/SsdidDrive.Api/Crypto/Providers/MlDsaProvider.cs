using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Pkcs;
using Org.BouncyCastle.Security;
using Org.BouncyCastle.X509;

namespace SsdidDrive.Api.Crypto.Providers;

/// <summary>
/// ML-DSA (FIPS 204) provider using BouncyCastle.
/// Keys are stored in X.509/DER (public) and PKCS#8/DER (private) format
/// for interoperability with the SSDID registry (Java/BouncyCastle JCA).
/// </summary>
public class MlDsaProvider : ICryptoProvider
{
    public string Family => "MlDsa";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var parameters = GetParameters(variant);
        var keyGen = new MLDsaKeyPairGenerator();
        keyGen.Init(new MLDsaKeyGenerationParameters(new SecureRandom(), parameters));

        var keyPair = keyGen.GenerateKeyPair();
        var pubKey = SubjectPublicKeyInfoFactory.CreateSubjectPublicKeyInfo(keyPair.Public).GetDerEncoded();
        var privKey = PrivateKeyInfoFactory.CreatePrivateKeyInfo(keyPair.Private).GetDerEncoded();
        return (pubKey, privKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var privKeyParams = (MLDsaPrivateKeyParameters)PrivateKeyFactory.CreateKey(privateKey);

        var signer = new MLDsaSigner(privKeyParams.Parameters, true);
        signer.Init(true, privKeyParams);
        signer.BlockUpdate(message, 0, message.Length);
        return signer.GenerateSignature();
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var pubKeyParams = (MLDsaPublicKeyParameters)PublicKeyFactory.CreateKey(publicKey);

            var signer = new MLDsaSigner(pubKeyParams.Parameters, true);
            signer.Init(false, pubKeyParams);
            signer.BlockUpdate(message, 0, message.Length);
            return signer.VerifySignature(signature);
        }
        catch
        {
            return false;
        }
    }

    private static MLDsaParameters GetParameters(string? variant) => variant switch
    {
        "MlDsa44" => MLDsaParameters.ml_dsa_44,
        "MlDsa65" => MLDsaParameters.ml_dsa_65,
        "MlDsa87" => MLDsaParameters.ml_dsa_87,
        _ => throw new ArgumentException($"Unsupported ML-DSA variant: {variant}")
    };
}
