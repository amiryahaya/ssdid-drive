using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Pkcs;
using Org.BouncyCastle.Security;
using Org.BouncyCastle.X509;

namespace SsdidDrive.Api.Crypto.Providers;

/// <summary>
/// SLH-DSA (FIPS 205) provider using BouncyCastle.
/// Keys are stored in X.509/DER (public) and PKCS#8/DER (private) format
/// for interoperability with the SSDID registry (Java/BouncyCastle JCA).
/// </summary>
public class SlhDsaProvider : ICryptoProvider
{
    public string Family => "SlhDsa";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var parameters = GetParameters(variant);
        var keyGen = new SlhDsaKeyPairGenerator();
        keyGen.Init(new SlhDsaKeyGenerationParameters(new SecureRandom(), parameters));

        var keyPair = keyGen.GenerateKeyPair();
        var pubKey = SubjectPublicKeyInfoFactory.CreateSubjectPublicKeyInfo(keyPair.Public).GetDerEncoded();
        var privKey = PrivateKeyInfoFactory.CreatePrivateKeyInfo(keyPair.Private).GetDerEncoded();
        return (pubKey, privKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var privKeyParams = (SlhDsaPrivateKeyParameters)PrivateKeyFactory.CreateKey(privateKey);

        var signer = new SlhDsaSigner(privKeyParams.Parameters, true);
        signer.Init(true, privKeyParams);
        signer.BlockUpdate(message, 0, message.Length);
        return signer.GenerateSignature();
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var pubKeyParams = (SlhDsaPublicKeyParameters)PublicKeyFactory.CreateKey(publicKey);

            var signer = new SlhDsaSigner(pubKeyParams.Parameters, true);
            signer.Init(false, pubKeyParams);
            signer.BlockUpdate(message, 0, message.Length);
            return signer.VerifySignature(signature);
        }
        catch
        {
            return false;
        }
    }

    private static SlhDsaParameters GetParameters(string? variant) => variant switch
    {
        "Sha2_128s" => SlhDsaParameters.slh_dsa_sha2_128s,
        "Sha2_128f" => SlhDsaParameters.slh_dsa_sha2_128f,
        "Sha2_192s" => SlhDsaParameters.slh_dsa_sha2_192s,
        "Sha2_192f" => SlhDsaParameters.slh_dsa_sha2_192f,
        "Sha2_256s" => SlhDsaParameters.slh_dsa_sha2_256s,
        "Sha2_256f" => SlhDsaParameters.slh_dsa_sha2_256f,
        "Shake_128s" => SlhDsaParameters.slh_dsa_shake_128s,
        "Shake_128f" => SlhDsaParameters.slh_dsa_shake_128f,
        "Shake_192s" => SlhDsaParameters.slh_dsa_shake_192s,
        "Shake_192f" => SlhDsaParameters.slh_dsa_shake_192f,
        "Shake_256s" => SlhDsaParameters.slh_dsa_shake_256s,
        "Shake_256f" => SlhDsaParameters.slh_dsa_shake_256f,
        _ => throw new ArgumentException($"Unsupported SLH-DSA variant: {variant}")
    };
}
