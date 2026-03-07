namespace SsdidDrive.Api.Crypto;

public class CryptoProviderFactory
{
    private readonly Dictionary<string, ICryptoProvider> _providers;

    public CryptoProviderFactory(IEnumerable<ICryptoProvider> providers)
    {
        _providers = providers.ToDictionary(p => p.Family);
    }

    public (ICryptoProvider Provider, string? Variant) Resolve(string vmType)
    {
        var algorithmId = AlgorithmRegistry.Resolve(vmType)
            ?? throw new ArgumentException($"Unsupported verification method type: {vmType}");

        if (!_providers.TryGetValue(algorithmId.Family, out var provider))
            throw new InvalidOperationException($"No crypto provider registered for family: {algorithmId.Family}");

        return (provider, algorithmId.Variant);
    }

    public byte[] Sign(string vmType, byte[] message, byte[] privateKey)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.Sign(message, privateKey, variant);
    }

    public bool Verify(string vmType, byte[] message, byte[] signature, byte[] publicKey)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.Verify(message, signature, publicKey, variant);
    }

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string vmType)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.GenerateKeyPair(variant);
    }

    public static string GetProofType(string vmType)
    {
        return AlgorithmRegistry.GetProofType(vmType)
            ?? throw new ArgumentException($"No proof type mapped for: {vmType}");
    }
}
