using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

namespace SsdidDrive.Api.Crypto.Providers;

public class Ed25519Provider : ICryptoProvider
{
    public string Family => "Ed25519";

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var gen = new Ed25519KeyPairGenerator();
        gen.Init(new Ed25519KeyGenerationParameters(new SecureRandom()));
        var pair = gen.GenerateKeyPair();

        var pubKey = ((Ed25519PublicKeyParameters)pair.Public).GetEncoded();
        var privKey = ((Ed25519PrivateKeyParameters)pair.Private).GetEncoded();
        return (pubKey, privKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var privParams = new Ed25519PrivateKeyParameters(privateKey);
        var signer = new Ed25519Signer();
        signer.Init(true, privParams);
        signer.BlockUpdate(message, 0, message.Length);
        return signer.GenerateSignature();
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var pubParams = new Ed25519PublicKeyParameters(publicKey);
            var verifier = new Ed25519Signer();
            verifier.Init(false, pubParams);
            verifier.BlockUpdate(message, 0, message.Length);
            return verifier.VerifySignature(signature);
        }
        catch
        {
            return false;
        }
    }
}
