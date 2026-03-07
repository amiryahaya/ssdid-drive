namespace SsdidDrive.Api.Crypto;

public record AlgorithmId(string Family, string? Variant);

public static class AlgorithmRegistry
{
    private static readonly Dictionary<string, AlgorithmId> VmTypeMap = new()
    {
        ["Ed25519VerificationKey2020"] = new("Ed25519", null),
        ["EcdsaSecp256r1VerificationKey2019"] = new("Ecdsa", "P256"),
        ["EcdsaSecp384VerificationKey2019"] = new("Ecdsa", "P384"),
        ["MlDsa44VerificationKey2024"] = new("MlDsa", "MlDsa44"),
        ["MlDsa65VerificationKey2024"] = new("MlDsa", "MlDsa65"),
        ["MlDsa87VerificationKey2024"] = new("MlDsa", "MlDsa87"),
        ["SlhDsaSha2128sVerificationKey2024"] = new("SlhDsa", "Sha2_128s"),
        ["SlhDsaSha2128fVerificationKey2024"] = new("SlhDsa", "Sha2_128f"),
        ["SlhDsaSha2192sVerificationKey2024"] = new("SlhDsa", "Sha2_192s"),
        ["SlhDsaSha2192fVerificationKey2024"] = new("SlhDsa", "Sha2_192f"),
        ["SlhDsaSha2256sVerificationKey2024"] = new("SlhDsa", "Sha2_256s"),
        ["SlhDsaSha2256fVerificationKey2024"] = new("SlhDsa", "Sha2_256f"),
        ["SlhDsaShake128sVerificationKey2024"] = new("SlhDsa", "Shake_128s"),
        ["SlhDsaShake128fVerificationKey2024"] = new("SlhDsa", "Shake_128f"),
        ["SlhDsaShake192sVerificationKey2024"] = new("SlhDsa", "Shake_192s"),
        ["SlhDsaShake192fVerificationKey2024"] = new("SlhDsa", "Shake_192f"),
        ["SlhDsaShake256sVerificationKey2024"] = new("SlhDsa", "Shake_256s"),
        ["SlhDsaShake256fVerificationKey2024"] = new("SlhDsa", "Shake_256f"),
        ["KazSignVerificationKey2024"] = new("KazSign", null),
    };

    private static readonly Dictionary<string, string> ProofTypeMap = new()
    {
        ["Ed25519VerificationKey2020"] = "Ed25519Signature2020",
        ["EcdsaSecp256r1VerificationKey2019"] = "EcdsaSecp256r1Signature2019",
        ["EcdsaSecp384VerificationKey2019"] = "EcdsaSecp384Signature2019",
        ["MlDsa44VerificationKey2024"] = "MlDsa44Signature2024",
        ["MlDsa65VerificationKey2024"] = "MlDsa65Signature2024",
        ["MlDsa87VerificationKey2024"] = "MlDsa87Signature2024",
        ["SlhDsaSha2128sVerificationKey2024"] = "SlhDsaSha2128sSignature2024",
        ["SlhDsaSha2128fVerificationKey2024"] = "SlhDsaSha2128fSignature2024",
        ["SlhDsaSha2192sVerificationKey2024"] = "SlhDsaSha2192sSignature2024",
        ["SlhDsaSha2192fVerificationKey2024"] = "SlhDsaSha2192fSignature2024",
        ["SlhDsaSha2256sVerificationKey2024"] = "SlhDsaSha2256sSignature2024",
        ["SlhDsaSha2256fVerificationKey2024"] = "SlhDsaSha2256fSignature2024",
        ["SlhDsaShake128sVerificationKey2024"] = "SlhDsaShake128sSignature2024",
        ["SlhDsaShake128fVerificationKey2024"] = "SlhDsaShake128fSignature2024",
        ["SlhDsaShake192sVerificationKey2024"] = "SlhDsaShake192sSignature2024",
        ["SlhDsaShake192fVerificationKey2024"] = "SlhDsaShake192fSignature2024",
        ["SlhDsaShake256sVerificationKey2024"] = "SlhDsaShake256sSignature2024",
        ["SlhDsaShake256fVerificationKey2024"] = "SlhDsaShake256fSignature2024",
        ["KazSignVerificationKey2024"] = "KazSignSignature2024",
    };

    private static readonly Dictionary<string, string> ReverseProofTypeMap =
        ProofTypeMap.ToDictionary(kv => kv.Value, kv => kv.Key);

    public static AlgorithmId? Resolve(string vmType) =>
        VmTypeMap.GetValueOrDefault(vmType);

    public static string? GetProofType(string vmType) =>
        ProofTypeMap.GetValueOrDefault(vmType);

    public static string? GetVmTypeFromProofType(string proofType) =>
        ReverseProofTypeMap.GetValueOrDefault(proofType);

    public static bool IsSupported(string vmType) =>
        VmTypeMap.ContainsKey(vmType);
}
