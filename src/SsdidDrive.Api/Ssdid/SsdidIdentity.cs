using System.Text.Json;
using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Ssdid;

public class SsdidIdentity
{
    public string Did { get; init; } = default!;
    public string KeyId { get; init; } = default!;
    public byte[] PublicKey { get; init; } = default!;
    public byte[] PrivateKey { get; init; } = default!;
    public string AlgorithmType { get; init; } = "KazSignVerificationKey2024";
    public bool AlgorithmMismatch { get; init; }

    private CryptoProviderFactory? _cryptoFactory;

    public void SetCryptoFactory(CryptoProviderFactory factory) => _cryptoFactory = factory;

    public static SsdidIdentity Create(string algorithmType, CryptoProviderFactory cryptoFactory)
    {
        var (pubKey, privKey) = cryptoFactory.GenerateKeyPair(algorithmType);
        var didSuffix = SsdidCrypto.Base64UrlEncode(
            System.Security.Cryptography.RandomNumberGenerator.GetBytes(16));
        var did = $"did:ssdid:{didSuffix}";
        var keyId = $"{did}#key-1";

        return new SsdidIdentity
        {
            Did = did,
            KeyId = keyId,
            PublicKey = pubKey,
            PrivateKey = privKey,
            AlgorithmType = algorithmType,
            _cryptoFactory = cryptoFactory
        };
    }

    public static SsdidIdentity LoadOrCreate(string path, string algorithmType, CryptoProviderFactory cryptoFactory)
    {
        if (File.Exists(path))
        {
            var json = File.ReadAllText(path);
            var data = JsonSerializer.Deserialize<IdentityData>(json)!;
            var loadedAlgorithm = data.AlgorithmType ?? "Ed25519VerificationKey2020";
            return new SsdidIdentity
            {
                Did = data.Did,
                KeyId = data.KeyId,
                PublicKey = SsdidCrypto.Base64UrlDecode(data.PublicKey),
                PrivateKey = SsdidCrypto.Base64UrlDecode(data.PrivateKey),
                AlgorithmType = loadedAlgorithm,
                AlgorithmMismatch = loadedAlgorithm != algorithmType,
                _cryptoFactory = cryptoFactory
            };
        }

        var identity = Create(algorithmType, cryptoFactory);

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        var saveData = new IdentityData(
            identity.Did, identity.KeyId,
            SsdidCrypto.Base64UrlEncode(identity.PublicKey),
            SsdidCrypto.Base64UrlEncode(identity.PrivateKey),
            identity.AlgorithmType);
        File.WriteAllText(path, JsonSerializer.Serialize(saveData,
            new JsonSerializerOptions { WriteIndented = true }));

        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path,
                UnixFileMode.UserRead | UnixFileMode.UserWrite);

        return identity;
    }

    /// <summary>
    /// Builds a W3C DID Document. Uses Dictionary to ensure "@context" serializes
    /// with the @ prefix (C# anonymous type @context would serialize as "context").
    /// </summary>
    public Dictionary<string, object> BuildDidDocument()
    {
        return new Dictionary<string, object>
        {
            ["@context"] = new[] { "https://www.w3.org/ns/did/v1" },
            ["id"] = Did,
            ["verificationMethod"] = new[]
            {
                new Dictionary<string, object>
                {
                    ["id"] = KeyId,
                    ["type"] = AlgorithmType,
                    ["controller"] = Did,
                    ["publicKeyMultibase"] = SsdidCrypto.MultibaseEncode(PublicKey)
                }
            },
            ["authentication"] = new[] { KeyId },
            ["assertionMethod"] = new[] { KeyId },
            ["capabilityInvocation"] = new[] { KeyId }
        };
    }

    public string SignChallenge(string challenge)
    {
        if (_cryptoFactory is null)
            throw new InvalidOperationException("CryptoFactory not set on SsdidIdentity");
        var messageBytes = System.Text.Encoding.UTF8.GetBytes(challenge);
        var signature = _cryptoFactory.Sign(AlgorithmType, messageBytes, PrivateKey);
        return SsdidCrypto.MultibaseEncode(signature);
    }

    public byte[] SignRaw(byte[] message)
    {
        if (_cryptoFactory is null)
            throw new InvalidOperationException("CryptoFactory not set on SsdidIdentity");
        return _cryptoFactory.Sign(AlgorithmType, message, PrivateKey);
    }

    private record IdentityData(string Did, string KeyId, string PublicKey, string PrivateKey, string? AlgorithmType = null);
}
