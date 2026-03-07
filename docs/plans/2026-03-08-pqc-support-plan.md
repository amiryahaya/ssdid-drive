# PQC Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full post-quantum cryptography support (19 algorithms, 5 families) to SsdidDrive.Api, matching the SSDID registry's capabilities.

**Architecture:** Strategy pattern with DI — `ICryptoProvider` per algorithm family, `CryptoProviderFactory` for dispatch. Native .NET 10 for ML-DSA/SLH-DSA/ECDSA, BouncyCastle for Ed25519, vendored P/Invoke for KAZ-Sign.

**Tech Stack:** .NET 10, System.Security.Cryptography (MLDsa, SlhDsa, ECDsa), BouncyCastle (Ed25519), KAZ-Sign native library (P/Invoke)

**Design doc:** `docs/plans/2026-03-08-pqc-support-design.md`

---

### Task 1: AlgorithmRegistry and ICryptoProvider Interface

**Files:**
- Create: `src/SsdidDrive.Api/Crypto/AlgorithmRegistry.cs`
- Create: `src/SsdidDrive.Api/Crypto/ICryptoProvider.cs`

**Step 1: Create `ICryptoProvider` interface**

```csharp
// src/SsdidDrive.Api/Crypto/ICryptoProvider.cs
namespace SsdidDrive.Api.Crypto;

public interface ICryptoProvider
{
    string Family { get; }
    (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null);
    byte[] Sign(byte[] message, byte[] privateKey, string? variant = null);
    bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null);
}
```

**Step 2: Create `AlgorithmRegistry`**

```csharp
// src/SsdidDrive.Api/Crypto/AlgorithmRegistry.cs
namespace SsdidDrive.Api.Crypto;

public record AlgorithmId(string Family, string? Variant);

public static class AlgorithmRegistry
{
    private static readonly Dictionary<string, AlgorithmId> VmTypeMap = new()
    {
        // Classical
        ["Ed25519VerificationKey2020"] = new("Ed25519", null),
        ["EcdsaSecp256r1VerificationKey2019"] = new("Ecdsa", "P256"),
        ["EcdsaSecp384VerificationKey2019"] = new("Ecdsa", "P384"),
        // ML-DSA (FIPS 204)
        ["MlDsa44VerificationKey2024"] = new("MlDsa", "MlDsa44"),
        ["MlDsa65VerificationKey2024"] = new("MlDsa", "MlDsa65"),
        ["MlDsa87VerificationKey2024"] = new("MlDsa", "MlDsa87"),
        // SLH-DSA (FIPS 205) — SHA2
        ["SlhDsaSha2128sVerificationKey2024"] = new("SlhDsa", "Sha2_128s"),
        ["SlhDsaSha2128fVerificationKey2024"] = new("SlhDsa", "Sha2_128f"),
        ["SlhDsaSha2192sVerificationKey2024"] = new("SlhDsa", "Sha2_192s"),
        ["SlhDsaSha2192fVerificationKey2024"] = new("SlhDsa", "Sha2_192f"),
        ["SlhDsaSha2256sVerificationKey2024"] = new("SlhDsa", "Sha2_256s"),
        ["SlhDsaSha2256fVerificationKey2024"] = new("SlhDsa", "Sha2_256f"),
        // SLH-DSA (FIPS 205) — SHAKE
        ["SlhDsaShake128sVerificationKey2024"] = new("SlhDsa", "Shake_128s"),
        ["SlhDsaShake128fVerificationKey2024"] = new("SlhDsa", "Shake_128f"),
        ["SlhDsaShake192sVerificationKey2024"] = new("SlhDsa", "Shake_192s"),
        ["SlhDsaShake192fVerificationKey2024"] = new("SlhDsa", "Shake_192f"),
        ["SlhDsaShake256sVerificationKey2024"] = new("SlhDsa", "Shake_256s"),
        ["SlhDsaShake256fVerificationKey2024"] = new("SlhDsa", "Shake_256f"),
        // KAZ-Sign
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

    // Reverse map: proof type → VM type
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
```

**Step 3: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/
git commit -m "feat: add AlgorithmRegistry and ICryptoProvider interface

19 W3C verification method type mappings with proof type maps.
ICryptoProvider strategy pattern interface for multi-algorithm support."
```

---

### Task 2: Ed25519Provider

**Files:**
- Create: `src/SsdidDrive.Api/Crypto/Providers/Ed25519Provider.cs`

**Step 1: Create `Ed25519Provider`**

Move existing BouncyCastle Ed25519 code from `SsdidCrypto.cs` into the provider:

```csharp
// src/SsdidDrive.Api/Crypto/Providers/Ed25519Provider.cs
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
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/Providers/Ed25519Provider.cs
git commit -m "feat: add Ed25519Provider using BouncyCastle"
```

---

### Task 3: EcdsaProvider

**Files:**
- Create: `src/SsdidDrive.Api/Crypto/Providers/EcdsaProvider.cs`

**Step 1: Create `EcdsaProvider`**

```csharp
// src/SsdidDrive.Api/Crypto/Providers/EcdsaProvider.cs
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
        // Uncompressed point: 0x04 || X || Y
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
        var keySize = curve.Oid?.FriendlyName == "nistP384" ? 48 : 32;
        var parameters = new ECParameters
        {
            Curve = curve,
            D = privateKey,
            Q = default // will be computed from D
        };
        // ECDsa.Create with D but no Q: .NET derives Q automatically
        // We need to import with Q, so generate a temporary key to get Q
        ecdsa.ImportParameters(RecoverPublicFromPrivate(curve, privateKey));
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

    private static ECParameters RecoverPublicFromPrivate(ECCurve curve, byte[] d)
    {
        using var temp = ECDsa.Create(curve);
        var fullParams = temp.ExportParameters(true);
        fullParams.D = d;
        using var keyed = ECDsa.Create();
        keyed.ImportParameters(fullParams);
        return keyed.ExportParameters(false);
    }
}
```

Note: The `RecoverPublicFromPrivate` helper is needed because .NET ECDSA requires Q (public point) for import. In practice, this provider is mainly used for *verification* of client signatures (we have their public key from DID Documents). Key generation and signing are only needed if the server is configured to use ECDSA as its identity algorithm.

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/Providers/EcdsaProvider.cs
git commit -m "feat: add EcdsaProvider using native .NET ECDsa (P-256, P-384)"
```

---

### Task 4: MlDsaProvider

**Files:**
- Modify: `src/SsdidDrive.Api/SsdidDrive.Api.csproj` (add SYSLIB5006 suppression)
- Create: `src/SsdidDrive.Api/Crypto/Providers/MlDsaProvider.cs`

**Step 1: Add `SYSLIB5006` warning suppression to `.csproj`**

In `src/SsdidDrive.Api/SsdidDrive.Api.csproj`, add to `<PropertyGroup>`:

```xml
<NoWarn>$(NoWarn);SYSLIB5006</NoWarn>
```

**Step 2: Create `MlDsaProvider`**

```csharp
// src/SsdidDrive.Api/Crypto/Providers/MlDsaProvider.cs
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
```

**Step 3: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded (no SYSLIB5006 warnings)

**Step 4: Commit**

```bash
git add src/SsdidDrive.Api/SsdidDrive.Api.csproj src/SsdidDrive.Api/Crypto/Providers/MlDsaProvider.cs
git commit -m "feat: add MlDsaProvider using native .NET 10 MLDsa (44, 65, 87)"
```

---

### Task 5: SlhDsaProvider

**Files:**
- Create: `src/SsdidDrive.Api/Crypto/Providers/SlhDsaProvider.cs`

**Step 1: Create `SlhDsaProvider`**

```csharp
// src/SsdidDrive.Api/Crypto/Providers/SlhDsaProvider.cs
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
        "Shake_128s" => SlhDsaAlgorithm.SlhDsaShake_128s,
        "Shake_128f" => SlhDsaAlgorithm.SlhDsaShake_128f,
        "Shake_192s" => SlhDsaAlgorithm.SlhDsaShake_192s,
        "Shake_192f" => SlhDsaAlgorithm.SlhDsaShake_192f,
        "Shake_256s" => SlhDsaAlgorithm.SlhDsaShake_256s,
        "Shake_256f" => SlhDsaAlgorithm.SlhDsaShake_256f,
        _ => throw new ArgumentException($"Unsupported SLH-DSA variant: {variant}")
    };
}
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/Providers/SlhDsaProvider.cs
git commit -m "feat: add SlhDsaProvider using native .NET 10 SlhDsa (12 variants)"
```

---

### Task 6: Vendor KAZ-Sign and Create KazSignProvider

**Files:**
- Copy: `/Users/amirrudinyahaya/Workspace/PQC-KAZ/SIGN/bindings/csharp/KazSign/KazSign.cs` → `src/SsdidDrive.Api/Crypto/Native/KazSign.cs`
- Copy: native libraries to `src/SsdidDrive.Api/runtimes/` (macOS arm64 at minimum for dev)
- Create: `src/SsdidDrive.Api/Crypto/Providers/KazSignProvider.cs`
- Modify: `src/SsdidDrive.Api/SsdidDrive.Api.csproj` (native lib references)

**Step 1: Copy vendored files**

```bash
mkdir -p src/SsdidDrive.Api/Crypto/Native
cp /Users/amirrudinyahaya/Workspace/PQC-KAZ/SIGN/bindings/csharp/KazSign/KazSign.cs \
   src/SsdidDrive.Api/Crypto/Native/KazSign.cs

# Copy native libraries for current dev platform (macOS arm64)
mkdir -p src/SsdidDrive.Api/runtimes/osx-arm64/native
cp /Users/amirrudinyahaya/Workspace/PQC-KAZ/SIGN/build/lib/libkazsign.dylib \
   src/SsdidDrive.Api/runtimes/osx-arm64/native/

# Copy for other platforms if available:
# mkdir -p src/SsdidDrive.Api/runtimes/osx-x64/native
# mkdir -p src/SsdidDrive.Api/runtimes/linux-x64/native
# mkdir -p src/SsdidDrive.Api/runtimes/linux-arm64/native
# mkdir -p src/SsdidDrive.Api/runtimes/win-x64/native
```

If `build/lib/libkazsign.dylib` does not exist, build it first:
```bash
cd /Users/amirrudinyahaya/Workspace/PQC-KAZ/SIGN && make shared-all
```

**Step 2: Add native lib references to `.csproj`**

Add to `src/SsdidDrive.Api/SsdidDrive.Api.csproj` inside a new `<ItemGroup>`:

```xml
<ItemGroup>
  <None Include="runtimes\osx-arm64\native\libkazsign.dylib" CopyToOutputDirectory="PreserveNewest" Link="runtimes\osx-arm64\native\libkazsign.dylib" />
  <!-- Add more RIDs as native libs become available -->
</ItemGroup>
```

**Step 3: Create `KazSignProvider`**

```csharp
// src/SsdidDrive.Api/Crypto/Providers/KazSignProvider.cs
using Antrapol.Kaz.Sign;

namespace SsdidDrive.Api.Crypto.Providers;

public class KazSignProvider : ICryptoProvider, IDisposable
{
    public string Family => "KazSign";

    // Default security level; variant is not used for KAZ-Sign in the registry
    // (single "KazSignVerificationKey2024" type), but we default to Level128
    // matching the registry's kaz_sign_128 default.
    private const SecurityLevel DefaultLevel = SecurityLevel.Level128;

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        signer.GenerateKeyPair(out var publicKey, out var secretKey);
        return (publicKey, secretKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        return signer.SignDetached(message, privateKey);
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            var level = InferLevelFromPublicKey(publicKey);
            using var signer = new KazSigner(level);
            return signer.VerifyDetached(message, signature, publicKey);
        }
        catch
        {
            return false;
        }
    }

    private static SecurityLevel ParseLevel(string? variant) => variant switch
    {
        "128" => SecurityLevel.Level128,
        "192" => SecurityLevel.Level192,
        "256" => SecurityLevel.Level256,
        null => DefaultLevel,
        _ => throw new ArgumentException($"Unsupported KAZ-Sign variant: {variant}")
    };

    // Infer security level from public key size during verification
    // (we only have the public key from the DID Document, no variant info).
    private static SecurityLevel InferLevelFromPublicKey(byte[] publicKey) => publicKey.Length switch
    {
        54 => SecurityLevel.Level128,
        88 => SecurityLevel.Level192,
        119 => SecurityLevel.Level256,
        _ => throw new ArgumentException($"Cannot infer KAZ-Sign level from public key size: {publicKey.Length}")
    };

    public void Dispose() { /* KazSigner instances are created per-operation */ }
}
```

**Step 4: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/Native/ src/SsdidDrive.Api/Crypto/Providers/KazSignProvider.cs \
        src/SsdidDrive.Api/runtimes/ src/SsdidDrive.Api/SsdidDrive.Api.csproj
git commit -m "feat: add KazSignProvider with vendored KAZ-Sign P/Invoke wrapper

Detached signatures via KazSigner. Infers security level from public key
size during verification. Default level 128 for key generation."
```

---

### Task 7: CryptoProviderFactory

**Files:**
- Create: `src/SsdidDrive.Api/Crypto/CryptoProviderFactory.cs`

**Step 1: Create `CryptoProviderFactory`**

```csharp
// src/SsdidDrive.Api/Crypto/CryptoProviderFactory.cs
namespace SsdidDrive.Api.Crypto;

public class CryptoProviderFactory
{
    private readonly Dictionary<string, ICryptoProvider> _providers;

    public CryptoProviderFactory(IEnumerable<ICryptoProvider> providers)
    {
        _providers = providers.ToDictionary(p => p.Family);
    }

    /// <summary>
    /// Resolve a W3C verification method type to its provider and variant.
    /// </summary>
    public (ICryptoProvider Provider, string? Variant) Resolve(string vmType)
    {
        var algorithmId = AlgorithmRegistry.Resolve(vmType)
            ?? throw new ArgumentException($"Unsupported verification method type: {vmType}");

        if (!_providers.TryGetValue(algorithmId.Family, out var provider))
            throw new InvalidOperationException($"No crypto provider registered for family: {algorithmId.Family}");

        return (provider, algorithmId.Variant);
    }

    /// <summary>
    /// Sign a message using the provider for the given verification method type.
    /// </summary>
    public byte[] Sign(string vmType, byte[] message, byte[] privateKey)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.Sign(message, privateKey, variant);
    }

    /// <summary>
    /// Verify a signature using the provider for the given verification method type.
    /// </summary>
    public bool Verify(string vmType, byte[] message, byte[] signature, byte[] publicKey)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.Verify(message, signature, publicKey, variant);
    }

    /// <summary>
    /// Generate a key pair using the provider for the given verification method type.
    /// </summary>
    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string vmType)
    {
        var (provider, variant) = Resolve(vmType);
        return provider.GenerateKeyPair(variant);
    }

    /// <summary>
    /// Get the W3C proof type string for a verification method type.
    /// </summary>
    public static string GetProofType(string vmType)
    {
        return AlgorithmRegistry.GetProofType(vmType)
            ?? throw new ArgumentException($"No proof type mapped for: {vmType}");
    }
}
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Crypto/CryptoProviderFactory.cs
git commit -m "feat: add CryptoProviderFactory for W3C type → provider dispatch"
```

---

### Task 8: Register Providers in DI (Program.cs)

**Files:**
- Modify: `src/SsdidDrive.Api/Program.cs:1-50`

**Step 1: Add DI registrations**

Add these `using` statements at the top of `Program.cs`:

```csharp
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
```

Add provider registrations after the existing `AddScoped<CurrentUserAccessor>()` line (line 30) and before the `// ── SSDID Services ──` comment (line 32):

```csharp
// ── Crypto Providers ──
builder.Services.AddSingleton<ICryptoProvider, Ed25519Provider>();
builder.Services.AddSingleton<ICryptoProvider, EcdsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, MlDsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, SlhDsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, KazSignProvider>();
builder.Services.AddSingleton<CryptoProviderFactory>();
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Program.cs
git commit -m "feat: register crypto providers and factory in DI"
```

---

### Task 9: Update SsdidIdentity for Configurable Algorithm

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/SsdidIdentity.cs` (full rewrite)
- Modify: `src/SsdidDrive.Api/Program.cs:32-36` (identity creation)
- Modify: `src/SsdidDrive.Api/appsettings.json` (add Algorithm key)

**Step 1: Update `SsdidIdentity`**

Rewrite `SsdidIdentity.cs` to use `CryptoProviderFactory`:

```csharp
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
            return new SsdidIdentity
            {
                Did = data.Did,
                KeyId = data.KeyId,
                PublicKey = SsdidCrypto.Base64UrlDecode(data.PublicKey),
                PrivateKey = SsdidCrypto.Base64UrlDecode(data.PrivateKey),
                AlgorithmType = data.AlgorithmType ?? "Ed25519VerificationKey2020",
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

    public object BuildDidDocument()
    {
        return new
        {
            @context = new[] { "https://www.w3.org/ns/did/v1" },
            id = Did,
            verificationMethod = new[]
            {
                new
                {
                    id = KeyId,
                    type = AlgorithmType,
                    controller = Did,
                    publicKeyMultibase = SsdidCrypto.MultibaseEncode(PublicKey)
                }
            },
            authentication = new[] { KeyId },
            assertionMethod = new[] { KeyId },
            capabilityInvocation = new[] { KeyId }
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

    private record IdentityData(string Did, string KeyId, string PublicKey, string PrivateKey, string? AlgorithmType = null);
}
```

**Step 2: Update `Program.cs` identity creation**

Replace lines 32-36 of `Program.cs` (the `// ── SSDID Services ──` section) with:

```csharp
// ── SSDID Services ──
var cryptoFactory = builder.Services.BuildServiceProvider().GetRequiredService<CryptoProviderFactory>();
var identityPath = builder.Configuration["Ssdid:IdentityPath"]
    ?? Path.Combine(builder.Environment.ContentRootPath, "data", "server-identity.json");
var algorithmType = builder.Configuration["Ssdid:Algorithm"] ?? "KazSignVerificationKey2024";
var identity = SsdidIdentity.LoadOrCreate(identityPath, algorithmType, cryptoFactory);
builder.Services.AddSingleton(identity);
```

**Step 3: Update `appsettings.json`**

Add `"Algorithm"` to the `"Ssdid"` section in `src/SsdidDrive.Api/appsettings.json`:

```json
{
  "Ssdid": {
    "Algorithm": "KazSignVerificationKey2024",
    "RegistryUrl": "https://registry.ssdid.my",
    "IdentityPath": "data/server-identity.json",
    "PreviousIdentities": []
  }
}
```

**Step 4: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/SsdidIdentity.cs src/SsdidDrive.Api/Program.cs \
        src/SsdidDrive.Api/appsettings.json
git commit -m "feat: make SsdidIdentity algorithm configurable via appsettings

Default algorithm: KazSignVerificationKey2024. LoadOrCreate reads algorithmType
from server-identity.json with Ed25519 backward compatibility."
```

---

### Task 10: Update RegistryClient to Return Algorithm Type

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/RegistryClient.cs:43-63`

**Step 1: Change `ExtractPublicKey` return type**

Replace the `ExtractPublicKey` method (lines 43-63) with:

```csharp
/// <summary>
/// Extract a public key and algorithm type from a DID Document by key ID.
/// Returns the raw public key bytes and the W3C verification method type.
/// </summary>
public static (byte[] PublicKey, string AlgorithmType)? ExtractPublicKey(JsonElement didDocument, string keyId)
{
    if (!didDocument.TryGetProperty("did_document", out var doc))
        doc = didDocument;

    if (!doc.TryGetProperty("verificationMethod", out var methods))
        return null;

    foreach (var method in methods.EnumerateArray())
    {
        var id = method.GetProperty("id").GetString();
        if (id != keyId) continue;

        var multibase = method.GetProperty("publicKeyMultibase").GetString();
        if (multibase is null) return null;

        var vmType = method.GetProperty("type").GetString();
        if (vmType is null) return null;

        return (SsdidCrypto.MultibaseDecode(multibase), vmType);
    }

    return null;
}
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build errors in `SsdidAuthService.cs` (callers expect `byte[]?`). This is expected — we fix them in Task 11.

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/RegistryClient.cs
git commit -m "feat: RegistryClient.ExtractPublicKey returns algorithm type alongside key"
```

---

### Task 11: Update SsdidAuthService for Multi-Algorithm Verification

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/SsdidAuthService.cs` (full rewrite)

**Step 1: Rewrite `SsdidAuthService`**

```csharp
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Ssdid;

public record RegisterResponse(string Challenge, string ServerDid, string ServerKeyId, string ServerSignature);
public record VerifyResponse(JsonElement Credential, string Did);
public record AuthenticateResponse(string SessionToken, string Did, string ServerDid, string ServerSignature);

public class SsdidAuthService
{
    private readonly SsdidIdentity _identity;
    private readonly SessionStore _sessionStore;
    private readonly RegistryClient _registryClient;
    private readonly CryptoProviderFactory _cryptoFactory;
    private readonly ILogger<SsdidAuthService> _logger;
    private readonly IReadOnlyDictionary<string, (byte[] PublicKey, string AlgorithmType)> _trustedKeys;

    private static readonly JsonSerializerOptions VcSerializerOptions = new() { WriteIndented = false };

    public SsdidAuthService(
        SsdidIdentity identity,
        SessionStore sessionStore,
        RegistryClient registryClient,
        CryptoProviderFactory cryptoFactory,
        IConfiguration config,
        ILogger<SsdidAuthService> logger)
    {
        _identity = identity;
        _sessionStore = sessionStore;
        _registryClient = registryClient;
        _cryptoFactory = cryptoFactory;
        _logger = logger;
        _trustedKeys = BuildTrustedKeys(identity, config);
    }

    private static IReadOnlyDictionary<string, (byte[] PublicKey, string AlgorithmType)> BuildTrustedKeys(
        SsdidIdentity identity, IConfiguration config)
    {
        var keys = new Dictionary<string, (byte[] PublicKey, string AlgorithmType)>
        {
            [identity.Did] = (identity.PublicKey, identity.AlgorithmType)
        };
        var previous = config.GetSection("Ssdid:PreviousIdentities").GetChildren();
        foreach (var entry in previous)
        {
            var did = entry["Did"];
            var pubKey = entry["PublicKey"];
            var algType = entry["AlgorithmType"] ?? "Ed25519VerificationKey2020";
            if (did is not null && pubKey is not null)
                keys[did] = (SsdidCrypto.Base64UrlDecode(pubKey), algType);
        }
        return keys.AsReadOnly();
    }

    public async Task<Result<RegisterResponse>> HandleRegister(string clientDid, string clientKeyId)
    {
        var didDoc = await _registryClient.ResolveDid(clientDid);
        if (didDoc is null)
        {
            _logger.LogWarning("Registration failed: DID not found {Did}", clientDid);
            return AppError.NotFound("DID not found in registry");
        }

        var challenge = SsdidCrypto.GenerateChallenge();
        var serverSignature = _identity.SignChallenge(challenge);
        _sessionStore.CreateChallenge(clientDid, "registration", challenge, clientKeyId);

        return new RegisterResponse(challenge, _identity.Did, _identity.KeyId, serverSignature);
    }

    public async Task<Result<VerifyResponse>> HandleVerifyResponse(string clientDid, string clientKeyId, string signedChallenge)
    {
        var entry = _sessionStore.ConsumeChallenge(clientDid, "registration");
        if (entry is null)
        {
            _logger.LogWarning("Verify failed: no challenge found for {Did}", clientDid);
            return AppError.Unauthorized("No pending challenge found or challenge expired");
        }

        if (entry.KeyId != clientKeyId)
        {
            _logger.LogWarning("Verify failed: key ID mismatch for {Did}", clientDid);
            return AppError.Unauthorized("Key ID does not match the pending challenge");
        }

        var didDoc = await _registryClient.ResolveDid(clientDid);
        if (didDoc is null)
            return AppError.NotFound("DID not found in registry");

        var extracted = RegistryClient.ExtractPublicKey(didDoc.Value, clientKeyId);
        if (extracted is null)
        {
            _logger.LogWarning("Verify failed: public key not found for {KeyId}", clientKeyId);
            return AppError.NotFound("Public key not found in DID Document");
        }

        var (publicKey, algorithmType) = extracted.Value;
        var signatureBytes = SsdidCrypto.MultibaseDecode(signedChallenge);
        var challengeBytes = Encoding.UTF8.GetBytes(entry.Challenge);

        if (!_cryptoFactory.Verify(algorithmType, challengeBytes, signatureBytes, publicKey))
        {
            _logger.LogWarning("Verify failed: invalid signature for {Did}", clientDid);
            return AppError.Unauthorized("Signature verification failed");
        }

        var credential = IssueCredential(clientDid);
        _logger.LogInformation("Registration verified for {Did}", clientDid);

        return new VerifyResponse(credential, clientDid);
    }

    public Result<AuthenticateResponse> HandleAuthenticate(JsonElement credential)
    {
        if (!VerifyCredentialOffline(credential))
        {
            _logger.LogWarning("Authentication failed: invalid credential");
            return AppError.Unauthorized("Invalid or expired credential");
        }

        var subjectDid = credential
            .GetProperty("credentialSubject")
            .GetProperty("id")
            .GetString();

        if (subjectDid is null)
            return AppError.Unauthorized("Credential missing subject DID");

        var sessionToken = _sessionStore.CreateSession(subjectDid);
        if (sessionToken is null)
        {
            _logger.LogWarning("Authentication failed: session limit reached");
            return AppError.ServiceUnavailable("Session limit reached, try again later");
        }

        var serverSignature = _identity.SignChallenge(sessionToken);
        _logger.LogInformation("Authenticated {Did}", subjectDid);

        return new AuthenticateResponse(sessionToken, subjectDid, _identity.Did, serverSignature);
    }

    public void RevokeSession(string token) => _sessionStore.DeleteSession(token);

    private static string BuildSigningInput(
        string vcId, string issuer, string issuanceDate,
        string expirationDate, string subjectDid, string service)
    {
        static string Lp(string s) => $"{s.Length}:{s}";
        return $"{Lp(vcId)};{Lp(issuer)};{Lp(issuanceDate)};{Lp(expirationDate)};{Lp(subjectDid)};{Lp(service)}";
    }

    private JsonElement IssueCredential(string subjectDid)
    {
        var now = DateTimeOffset.UtcNow;
        var vcId = $"urn:uuid:{Guid.NewGuid()}";
        var issuanceDate = now.ToString("o");
        var expirationDate = now.AddDays(365).ToString("o");

        var signingInput = BuildSigningInput(
            vcId, _identity.Did, issuanceDate, expirationDate, subjectDid, "drive");
        var proofBytes = _cryptoFactory.Sign(
            _identity.AlgorithmType,
            Encoding.UTF8.GetBytes(signingInput),
            _identity.PrivateKey);

        var proofType = CryptoProviderFactory.GetProofType(_identity.AlgorithmType);

        var vc = new
        {
            @context = new[] { "https://www.w3.org/2018/credentials/v1" },
            id = vcId,
            type = new[] { "VerifiableCredential", "SsdidRegistrationCredential" },
            issuer = _identity.Did,
            issuanceDate,
            expirationDate,
            credentialSubject = new
            {
                id = subjectDid,
                service = "drive",
                registeredAt = issuanceDate
            },
            proof = new
            {
                type = proofType,
                created = now.ToString("o"),
                verificationMethod = _identity.KeyId,
                proofPurpose = "assertionMethod",
                proofValue = SsdidCrypto.MultibaseEncode(proofBytes)
            }
        };

        return JsonSerializer.SerializeToElement(vc, VcSerializerOptions);
    }

    private bool VerifyCredentialOffline(JsonElement credential)
    {
        try
        {
            var issuer = credential.GetProperty("issuer").GetString();
            if (issuer is null || !_trustedKeys.TryGetValue(issuer, out var trustedKey))
            {
                _logger.LogWarning("VC verification failed: untrusted issuer {Issuer}", issuer);
                return false;
            }

            if (!credential.TryGetProperty("id", out var idEl) ||
                !credential.TryGetProperty("issuanceDate", out var issuanceDateEl) ||
                !credential.TryGetProperty("expirationDate", out var expirationDateEl) ||
                !credential.TryGetProperty("credentialSubject", out var subject) ||
                !subject.TryGetProperty("id", out var subjectDidEl) ||
                !subject.TryGetProperty("service", out var serviceEl) ||
                !credential.TryGetProperty("proof", out var proof) ||
                !proof.TryGetProperty("proofValue", out var proofValueEl))
            {
                _logger.LogWarning("VC verification failed: missing required properties");
                return false;
            }

            var vcId = idEl.GetString();
            var issuanceDate = issuanceDateEl.GetString();
            var expirationDate = expirationDateEl.GetString();
            var subjectDid = subjectDidEl.GetString();
            var service = serviceEl.GetString();
            var proofValue = proofValueEl.GetString();

            if (vcId is null || issuanceDate is null || expirationDate is null ||
                subjectDid is null || service is null || proofValue is null)
            {
                _logger.LogWarning("VC verification failed: null property values");
                return false;
            }

            var exp = DateTimeOffset.Parse(expirationDate);
            if (exp < DateTimeOffset.UtcNow) return false;

            var signingInput = BuildSigningInput(vcId, issuer, issuanceDate, expirationDate, subjectDid, service);
            var sigBytes = SsdidCrypto.MultibaseDecode(proofValue);
            var msgBytes = Encoding.UTF8.GetBytes(signingInput);

            return _cryptoFactory.Verify(trustedKey.AlgorithmType, msgBytes, sigBytes, trustedKey.PublicKey);
        }
        catch (FormatException ex)
        {
            _logger.LogWarning(ex, "VC verification failed: invalid date or encoding format");
            return false;
        }
    }
}
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/SsdidAuthService.cs
git commit -m "feat: SsdidAuthService uses CryptoProviderFactory for multi-algorithm verification

Trusted keys now carry algorithm type. IssueCredential uses server's configured
algorithm. HandleVerifyResponse dispatches to correct provider based on client's
DID Document verification method type."
```

---

### Task 12: Update ServerRegistrationService

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/ServerRegistrationService.cs:43-54`

**Step 1: Update proof construction**

Replace the hardcoded `"Ed25519Signature2020"` proof type and `SsdidCrypto.Sign` call (lines 43-54) with:

```csharp
var docJson = JsonSerializer.Serialize(didDoc);
var proofBytes = identity.SignChallengeRaw(Encoding.UTF8.GetBytes(docJson));
var proofType = CryptoProviderFactory.GetProofType(identity.AlgorithmType);
var proof = new
{
    type = proofType,
    created = DateTimeOffset.UtcNow.ToString("o"),
    verificationMethod = identity.KeyId,
    proofPurpose = "assertionMethod",
    proofValue = SsdidCrypto.MultibaseEncode(proofBytes)
};
```

This requires adding a `SignChallengeRaw` method to `SsdidIdentity` that takes `byte[]` directly (the existing `SignChallenge` takes a string). Add to `SsdidIdentity.cs`:

```csharp
public byte[] SignChallengeRaw(byte[] message)
{
    if (_cryptoFactory is null)
        throw new InvalidOperationException("CryptoFactory not set on SsdidIdentity");
    return _cryptoFactory.Sign(AlgorithmType, message, PrivateKey);
}
```

Also add `using SsdidDrive.Api.Crypto;` to `ServerRegistrationService.cs`.

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/ServerRegistrationService.cs src/SsdidDrive.Api/Ssdid/SsdidIdentity.cs
git commit -m "feat: ServerRegistrationService uses configured algorithm for proof signing"
```

---

### Task 13: Slim Down SsdidCrypto

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/SsdidCrypto.cs`

**Step 1: Remove crypto operations, keep encoding utilities**

Remove the `GenerateEd25519KeyPair`, `Sign`, and `Verify` methods (lines 16-60) and the BouncyCastle using statements (lines 2-6). The file should become:

```csharp
using System.Security.Cryptography;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Encoding utilities for SSDID: Base64url, multibase, challenge generation.
/// </summary>
public static class SsdidCrypto
{
    public static string GenerateChallenge()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64UrlEncode(bytes);
    }

    public static string Base64UrlEncode(byte[] data)
    {
        return Convert.ToBase64String(data)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }

    public static byte[] Base64UrlDecode(string input)
    {
        var s = input.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }

    public static string MultibaseEncode(byte[] data) => "u" + Base64UrlEncode(data);

    public static byte[] MultibaseDecode(string multibase)
    {
        if (string.IsNullOrEmpty(multibase) || multibase[0] != 'u')
            throw new ArgumentException("Invalid multibase encoding (expected 'u' prefix)");

        return Base64UrlDecode(multibase[1..]);
    }
}
```

**Step 2: Verify it builds**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded (no remaining references to the removed methods)

**Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/SsdidCrypto.cs
git commit -m "refactor: slim SsdidCrypto to encoding utilities only

Crypto operations moved to ICryptoProvider implementations."
```

---

### Task 14: Final Build Verification and Smoke Test

**Files:** None (verification only)

**Step 1: Clean build**

Run: `dotnet clean src/SsdidDrive.Api && dotnet build src/SsdidDrive.Api`
Expected: Build succeeded, 0 errors, 0 warnings

**Step 2: Delete existing `server-identity.json` (will regenerate with KAZ-Sign)**

```bash
rm -f src/SsdidDrive.Api/data/server-identity.json
rm -f src/SsdidDrive.Api/bin/Debug/net10.0/Data/server-identity.json
```

**Step 3: Start the application**

Run: `dotnet run --project src/SsdidDrive.Api`
Expected: Application starts. Logs show:
- `Server DID registered: did:ssdid:...` (or retry warnings if registry is unreachable)
- New `data/server-identity.json` is created with `"AlgorithmType": "KazSignVerificationKey2024"`

**Step 4: Test the server-info endpoint**

Run: `curl -s http://localhost:5000/api/auth/ssdid/server-info | python3 -m json.tool`
Expected: Response includes the server DID and key ID.

**Step 5: Verify `server-identity.json` contains KAZ-Sign algorithm type**

Run: `cat src/SsdidDrive.Api/data/server-identity.json`
Expected: JSON with `"AlgorithmType": "KazSignVerificationKey2024"`

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: PQC support complete — 19 algorithms across 5 families

Server identity now defaults to KAZ-Sign. All verification method types from
the SSDID registry are supported: Ed25519, ECDSA (P-256, P-384), ML-DSA
(44, 65, 87), SLH-DSA (12 SHA2/SHAKE variants), and KAZ-Sign."
```
