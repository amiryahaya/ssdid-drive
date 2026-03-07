# PQC Support Design

Full post-quantum cryptography support for SsdidDrive.Api, achieving algorithm parity with the SSDID registry (19 algorithms across 5 families).

## Decisions

- **Default server algorithm:** KAZ-Sign (`KazSignVerificationKey2024`)
- **Configurable** via `appsettings.json` key `Ssdid:Algorithm`
- **Strategy pattern** with DI — `ICryptoProvider` interface, one implementation per algorithm family
- **Native .NET 10** for ML-DSA (FIPS 204) and SLH-DSA (FIPS 205), suppress `SYSLIB5006`
- **Native .NET** for ECDSA P-256/P-384
- **BouncyCastle** retained only for Ed25519
- **Vendored P/Invoke** for KAZ-Sign from `/Users/amirrudinyahaya/Workspace/PQC-KAZ/SIGN/bindings/csharp/`

## Algorithm Registry

Static `AlgorithmRegistry` maps W3C verification method types to provider families and variants:

| W3C Verification Method Type | Family | Variant |
|---|---|---|
| `Ed25519VerificationKey2020` | Ed25519 | — |
| `EcdsaSecp256r1VerificationKey2019` | Ecdsa | P256 |
| `EcdsaSecp384VerificationKey2019` | Ecdsa | P384 |
| `MlDsa44VerificationKey2024` | MlDsa | MlDsa44 |
| `MlDsa65VerificationKey2024` | MlDsa | MlDsa65 |
| `MlDsa87VerificationKey2024` | MlDsa | MlDsa87 |
| `SlhDsaSha2128sVerificationKey2024` | SlhDsa | Sha2_128s |
| `SlhDsaSha2128fVerificationKey2024` | SlhDsa | Sha2_128f |
| `SlhDsaSha2192sVerificationKey2024` | SlhDsa | Sha2_192s |
| `SlhDsaSha2192fVerificationKey2024` | SlhDsa | Sha2_192f |
| `SlhDsaSha2256sVerificationKey2024` | SlhDsa | Sha2_256s |
| `SlhDsaSha2256fVerificationKey2024` | SlhDsa | Sha2_256f |
| `SlhDsaShake128sVerificationKey2024` | SlhDsa | Shake_128s |
| `SlhDsaShake128fVerificationKey2024` | SlhDsa | Shake_128f |
| `SlhDsaShake192sVerificationKey2024` | SlhDsa | Shake_192s |
| `SlhDsaShake192fVerificationKey2024` | SlhDsa | Shake_192f |
| `SlhDsaShake256sVerificationKey2024` | SlhDsa | Shake_256s |
| `SlhDsaShake256fVerificationKey2024` | SlhDsa | Shake_256f |
| `KazSignVerificationKey2024` | KazSign | — |

Matching proof type map (e.g. `Ed25519Signature2020`, `KazSignSignature2024`).

An `AlgorithmId` record holds `(Family, Variant)`.

## ICryptoProvider Interface

```csharp
public interface ICryptoProvider
{
    string Family { get; }
    (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null);
    byte[] Sign(byte[] message, byte[] privateKey, string? variant = null);
    bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null);
}
```

## Provider Implementations

| Provider | Backend | Algorithms |
|---|---|---|
| `Ed25519Provider` | BouncyCastle | 1 |
| `EcdsaProvider` | `System.Security.Cryptography.ECDsa` | 2 (P-256, P-384) |
| `MlDsaProvider` | `System.Security.Cryptography.MLDsa` | 3 (44, 65, 87) |
| `SlhDsaProvider` | `System.Security.Cryptography.SlhDsa` | 12 (SHA2/SHAKE variants) |
| `KazSignProvider` | Vendored `KazSigner` P/Invoke | 1 (level 128/192/256 at runtime) |

All registered as `IEnumerable<ICryptoProvider>` singletons in DI.

## CryptoProviderFactory

Injected service that indexes providers by family. Exposes:

```csharp
ICryptoProvider GetProvider(string vmType);
(ICryptoProvider Provider, string? Variant) Resolve(string vmType);
```

## SsdidIdentity Changes

- `AlgorithmType` read from `Ssdid:Algorithm` config (default: `KazSignVerificationKey2024`)
- `LoadOrCreate` receives `CryptoProviderFactory` to generate keys / sign with the configured provider
- `server-identity.json` gains `algorithmType` field; defaults to `Ed25519VerificationKey2020` if absent (backward compat)
- `BuildDidDocument()` uses stored `AlgorithmType` for verification method `type`
- `SignChallenge()` routes through the resolved provider

## Verification & Auth Flow

- `RegistryClient.ExtractPublicKey` returns `(byte[] PublicKey, string AlgorithmType)?` (was `byte[]?`)
- `SsdidAuthService._trustedKeys` becomes `Dictionary<string, (byte[] PublicKey, string AlgorithmType)>`
- `VerifyCredentialOffline` extracts `proof.type`, maps to algorithm, resolves provider, verifies
- `HandleVerifyResponse` uses extracted algorithm type from DID Document for client signature verification
- `IssueCredential` uses the server's configured provider for proof signing

## SsdidCrypto Changes

Slimmed to encoding utilities only:
- `GenerateChallenge()`, `Base64UrlEncode/Decode`, `MultibaseEncode/Decode`
- Crypto operations (`GenerateEd25519KeyPair`, `Sign`, `Verify`) removed — moved to providers

## File Layout

```
src/SsdidDrive.Api/
  Crypto/
    AlgorithmRegistry.cs
    ICryptoProvider.cs
    CryptoProviderFactory.cs
    Providers/
      Ed25519Provider.cs
      EcdsaProvider.cs
      MlDsaProvider.cs
      SlhDsaProvider.cs
      KazSignProvider.cs
    Native/
      KazSign.cs                  (vendored from PQC-KAZ)
  runtimes/
    osx-arm64/native/libkazsign.dylib
    osx-x64/native/libkazsign.dylib
    linux-x64/native/libkazsign.so
    linux-arm64/native/libkazsign.so
    win-x64/native/kazsign.dll
    win-arm64/native/kazsign.dll
```

## .csproj Changes

- Native lib items with `CopyToOutputDirectory="PreserveNewest"` per RID
- `<NoWarn>$(NoWarn);SYSLIB5006</NoWarn>` for ML-DSA/SLH-DSA experimental APIs
- BouncyCastle dependency remains (Ed25519 only)

## Files Modified

- `SsdidCrypto.cs` — slim to encoding utilities
- `SsdidIdentity.cs` — configurable algorithm, provider-based key gen/signing
- `SsdidAuthService.cs` — inject `CryptoProviderFactory`, dispatch verification
- `RegistryClient.cs` — return algorithm type alongside public key
- `Program.cs` — register providers and factory in DI
- `SsdidDrive.Api.csproj` — native libs, warning suppression
- `appsettings.json` — default `Ssdid:Algorithm` to `KazSignVerificationKey2024`

## Files Unchanged

- `SsdidAuthMiddleware.cs` — session token lookup only
- `SessionStore.cs` — no crypto
- `CurrentUserAccessor.cs`, `AppError.cs`, `Result.cs`, `GlobalExceptionHandler.cs`
- All entity classes, migrations, endpoint files
