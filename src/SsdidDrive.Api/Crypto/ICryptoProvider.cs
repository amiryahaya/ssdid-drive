namespace SsdidDrive.Api.Crypto;

public interface ICryptoProvider
{
    string Family { get; }
    (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null);
    byte[] Sign(byte[] message, byte[] privateKey, string? variant = null);
    bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null);
}
