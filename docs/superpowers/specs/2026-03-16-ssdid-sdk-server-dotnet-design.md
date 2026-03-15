# Ssdid.Sdk.Server (.NET) — Design Spec

## Goal

Extract reusable SSDID protocol logic from ssdid-drive into a standalone C# server SDK. Any .NET app can add DID-based authentication with post-quantum cryptography by installing NuGet packages.

## Repo

`~/Workspace/ssdid-sdk-dotnet` — new repository, separate from ssdid-drive.

## Package Structure

3 NuGet packages with pluggable crypto:

```
Ssdid.Sdk.Server              ← Core: auth, identity, registry, sessions, Ed25519 + ECDSA
Ssdid.Sdk.Server.PqcNist      ← Optional: ML-DSA, SLH-DSA (BouncyCastle)
Ssdid.Sdk.Server.KazSign      ← Optional: KAZ-Sign (native libkazsign P/Invoke)
```

### Dependency Graph

```
Ssdid.Sdk.Server.KazSign ──→ Ssdid.Sdk.Server
Ssdid.Sdk.Server.PqcNist ──→ Ssdid.Sdk.Server
                              Ssdid.Sdk.Server ──→ BouncyCastle (Ed25519 only)
                                                ──→ StackExchange.Redis (optional, Redis session store)
                                                ──→ Microsoft.Extensions.* (DI, logging, caching)
```

## Solution Layout

```
ssdid-sdk-dotnet/
├── src/
│   ├── Ssdid.Sdk.Server/
│   │   ├── Auth/
│   │   │   ├── SsdidAuthService.cs          # Challenge-response, VC issuance/verification
│   │   │   ├── RegisterResponse.cs          # DTOs
│   │   │   ├── VerifyResponse.cs
│   │   │   └── AuthenticateResponse.cs
│   │   ├── Crypto/
│   │   │   ├── ICryptoProvider.cs            # Strategy interface
│   │   │   ├── AlgorithmRegistry.cs          # W3C type ↔ provider mapping (19 algorithms)
│   │   │   ├── CryptoProviderFactory.cs      # DI-based dispatch
│   │   │   └── Providers/
│   │   │       ├── Ed25519Provider.cs        # BouncyCastle
│   │   │       └── EcdsaProvider.cs          # System.Security.Cryptography
│   │   ├── Encoding/
│   │   │   └── SsdidEncoding.cs             # Base64url, multibase, SHA3, canonical JSON
│   │   ├── Identity/
│   │   │   └── SsdidIdentity.cs             # Server DID, keypair, DID Document builder
│   │   ├── Registry/
│   │   │   └── RegistryClient.cs            # DID resolution + registration
│   │   ├── Session/
│   │   │   ├── ISessionStore.cs             # Interface
│   │   │   ├── ISseNotificationBus.cs       # Interface
│   │   │   ├── SessionStoreOptions.cs       # Config
│   │   │   ├── ChallengeEntry.cs            # Record
│   │   │   ├── InMemory/
│   │   │   │   └── InMemorySessionStore.cs  # Single-instance impl
│   │   │   └── Redis/
│   │   │       └── RedisSessionStore.cs     # Distributed impl
│   │   ├── Registration/
│   │   │   └── ServerRegistrationService.cs # IHostedService for DID registration
│   │   ├── SsdidServerOptions.cs            # Root config
│   │   └── ServiceCollectionExtensions.cs   # AddSsdidServer()
│   │
│   ├── Ssdid.Sdk.Server.PqcNist/
│   │   ├── Providers/
│   │   │   ├── MlDsaProvider.cs
│   │   │   └── SlhDsaProvider.cs
│   │   └── ServiceCollectionExtensions.cs   # AddSsdidPqcNist()
│   │
│   └── Ssdid.Sdk.Server.KazSign/
│       ├── Providers/
│       │   └── KazSignProvider.cs
│       ├── Native/
│       │   └── KazSign.cs                   # P/Invoke wrapper
│       └── ServiceCollectionExtensions.cs   # AddSsdidKazSign()
│
├── tests/
│   ├── Ssdid.Sdk.Server.Tests/
│   │   ├── Auth/
│   │   │   └── SsdidAuthServiceTests.cs
│   │   ├── Crypto/
│   │   │   ├── AlgorithmRegistryTests.cs
│   │   │   └── CryptoProviderFactoryTests.cs
│   │   ├── Encoding/
│   │   │   └── SsdidEncodingTests.cs
│   │   ├── Identity/
│   │   │   └── SsdidIdentityTests.cs
│   │   ├── Registry/
│   │   │   └── RegistryClientTests.cs
│   │   └── Session/
│   │       ├── InMemorySessionStoreTests.cs
│   │       └── RedisSessionStoreTests.cs
│   ├── Ssdid.Sdk.Server.PqcNist.Tests/
│   └── Ssdid.Sdk.Server.KazSign.Tests/
│
├── Ssdid.Sdk.Server.sln
├── README.md
├── LICENSE
└── .github/
    └── workflows/
        └── ci.yml
```

## What Gets Extracted (ssdid-drive → SDK)

| ssdid-drive source | SDK destination | Package |
|---|---|---|
| `Ssdid/SsdidAuthService.cs` | `Auth/SsdidAuthService.cs` | Core |
| `Ssdid/SsdidCrypto.cs` | `Encoding/SsdidEncoding.cs` | Core |
| `Ssdid/SsdidIdentity.cs` | `Identity/SsdidIdentity.cs` | Core |
| `Ssdid/RegistryClient.cs` | `Registry/RegistryClient.cs` | Core |
| `Ssdid/SessionStore.cs` | `Session/InMemory/InMemorySessionStore.cs` | Core |
| `Ssdid/RedisSessionStore.cs` | `Session/Redis/RedisSessionStore.cs` | Core |
| `Ssdid/SessionStoreOptions.cs` | `Session/SessionStoreOptions.cs` | Core |
| `Ssdid/ISessionStore` (interface) | `Session/ISessionStore.cs` | Core |
| `Ssdid/ISseNotificationBus` (interface) | `Session/ISseNotificationBus.cs` | Core |
| `Crypto/ICryptoProvider.cs` | `Crypto/ICryptoProvider.cs` | Core |
| `Crypto/AlgorithmRegistry.cs` | `Crypto/AlgorithmRegistry.cs` | Core |
| `Crypto/CryptoProviderFactory.cs` | `Crypto/CryptoProviderFactory.cs` | Core |
| `Crypto/Providers/Ed25519Provider.cs` | `Crypto/Providers/Ed25519Provider.cs` | Core |
| `Crypto/Providers/EcdsaProvider.cs` | `Crypto/Providers/EcdsaProvider.cs` | Core |
| `Crypto/Providers/MlDsaProvider.cs` | `Providers/MlDsaProvider.cs` | PqcNist |
| `Crypto/Providers/SlhDsaProvider.cs` | `Providers/SlhDsaProvider.cs` | PqcNist |
| `Crypto/Providers/KazSignProvider.cs` | `Providers/KazSignProvider.cs` | KazSign |
| `Crypto/Native/KazSign.cs` | `Native/KazSign.cs` | KazSign |

## What Stays in ssdid-drive

- Auth endpoints (Register, RegisterVerify, Authenticate, LoginInitiate)
- User/Tenant provisioning logic (ProvisionUser, invite handling)
- SsdidAuthMiddleware (DB lookups, MFA, account status)
- Application-specific configuration (AdminDid, requested claims)
- AppDbContext and all entity/migration code

## Consumer API

### Setup

```csharp
// Program.cs — ssdid-drive (or any .NET app)
builder.Services.AddSsdidServer(options => {
    options.RegistryUrl = "https://registry.ssdid.my";
    options.IdentityPath = "data/server-identity.json";
    options.Algorithm = "KazSignVerificationKey2024";
    options.Sessions.SessionTtlMinutes = 60;
    options.Sessions.ChallengeTtlMinutes = 5;
});

// Optional: add post-quantum NIST algorithms
builder.Services.AddSsdidPqcNist();

// Optional: add KAZ-Sign
builder.Services.AddSsdidKazSign();

// Optional: use Redis instead of in-memory sessions
builder.Services.AddSsdidRedisSessionStore(connectionString);
```

### Usage in Endpoints

```csharp
// Registration
app.MapPost("/api/auth/register", (RegisterRequest req, SsdidAuthService auth) => {
    var result = await auth.HandleRegister(req.Did, req.KeyId);
    return result.Match(ok => Results.Ok(ok), err => err.ToProblemResult());
});

// Verify challenge response
app.MapPost("/api/auth/verify", (VerifyRequest req, SsdidAuthService auth) => {
    var result = await auth.HandleVerifyResponse(req.Did, req.KeyId, req.SignedChallenge);
    // result.Value.Credential is a W3C VC JsonElement
});

// Authenticate with VC
app.MapPost("/api/auth/authenticate", (AuthRequest req, SsdidAuthService auth) => {
    var result = auth.VerifyCredential(req.Credential);
    // result.Value is the verified DID
});
```

## Configuration

```csharp
public class SsdidServerOptions
{
    public string RegistryUrl { get; set; } = "https://registry.ssdid.my";
    public string IdentityPath { get; set; } = "data/server-identity.json";
    public string Algorithm { get; set; } = "Ed25519VerificationKey2020";
    public SessionStoreOptions Sessions { get; set; } = new();
    public string[] PreviousIdentities { get; set; } = [];  // For key rotation
}
```

## Error Handling

SDK returns `Result<T>` for all fallible operations:

```csharp
public readonly struct Result<T>
{
    public T? Value { get; }
    public SsdidError? Error { get; }
    public bool IsSuccess => Error is null;
}

public record SsdidError(string Code, string Message, int? HttpStatus = null);
```

Consumers map errors to their preferred HTTP response format. The SDK does not depend on ASP.NET Core — it works in any .NET host.

## Target Framework

- `net10.0` — matching ssdid-drive
- C# 13 with nullable reference types
- `[Experimental]` attribute on ML-DSA and SLH-DSA providers (SYSLIB5006)

## Testing Strategy

- Unit tests for each component (encoding, crypto, auth service, session stores)
- Integration tests for RegistryClient (mock HTTP)
- Integration tests for RedisSessionStore (Testcontainers)
- Crypto round-trip tests for all 19 algorithms
- Port existing tests from ssdid-drive `tests/SsdidDrive.Api.Tests/Crypto/` and `tests/SsdidDrive.Api.Tests/Ssdid/`
