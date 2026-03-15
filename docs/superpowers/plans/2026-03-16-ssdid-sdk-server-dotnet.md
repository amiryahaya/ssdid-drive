# Ssdid.Sdk.Server (.NET) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract SSDID protocol logic from ssdid-drive into a standalone C# server SDK (3 NuGet packages) in a new repo.

**Architecture:** Copy ~3200 lines of protocol code from `ssdid-drive/src/SsdidDrive.Api/{Ssdid,Crypto}/` into a new `ssdid-sdk-dotnet` solution with 3 projects. Re-namespace from `SsdidDrive.Api.*` to `Ssdid.Sdk.Server.*`. Add DI extensions for easy consumption. Port ~1500 lines of existing tests.

**Tech Stack:** .NET 10, C# 13, xUnit v3, BouncyCastle (Ed25519), StackExchange.Redis (optional), Microsoft.Extensions.DependencyInjection

**Repos:**
- New: `~/Workspace/ssdid-sdk-dotnet/`
- Source: `~/Workspace/ssdid-drive/`

---

## Extraction Strategy

This is primarily a **copy + re-namespace + clean up** operation:

1. Create new repo + solution structure
2. Copy source files, change namespace from `SsdidDrive.Api.{Ssdid,Crypto}` to `Ssdid.Sdk.Server.*`
3. Remove app-specific dependencies (AppDbContext, CurrentUserAccessor, etc.)
4. Add DI extension methods
5. Port tests with namespace changes
6. Update ssdid-drive to consume the SDK instead of inline code

## Source → Destination Map

### Core Package (Ssdid.Sdk.Server)

| Source (ssdid-drive) | Destination (SDK) | Lines |
|---|---|---|
| `Ssdid/SsdidAuthService.cs` | `src/Ssdid.Sdk.Server/Auth/SsdidAuthService.cs` | 303 |
| `Ssdid/SsdidCrypto.cs` | `src/Ssdid.Sdk.Server/Encoding/SsdidEncoding.cs` | 129 |
| `Ssdid/SsdidIdentity.cs` | `src/Ssdid.Sdk.Server/Identity/SsdidIdentity.cs` | 120 |
| `Ssdid/RegistryClient.cs` | `src/Ssdid.Sdk.Server/Registry/RegistryClient.cs` | 114 |
| `Ssdid/ISessionStore.cs` | `src/Ssdid.Sdk.Server/Session/ISessionStore.cs` | 32 |
| `Ssdid/ISseNotificationBus.cs` | `src/Ssdid.Sdk.Server/Session/ISseNotificationBus.cs` | 13 |
| `Ssdid/SessionStoreOptions.cs` | `src/Ssdid.Sdk.Server/Session/SessionStoreOptions.cs` | 22 |
| `Ssdid/SessionStore.cs` | `src/Ssdid.Sdk.Server/Session/InMemory/InMemorySessionStore.cs` | 234 |
| `Ssdid/RedisSessionStore.cs` | `src/Ssdid.Sdk.Server/Session/Redis/RedisSessionStore.cs` | 342 |
| `Ssdid/ServerRegistrationService.cs` | `src/Ssdid.Sdk.Server/Registration/ServerRegistrationService.cs` | 92 |
| `Crypto/ICryptoProvider.cs` | `src/Ssdid.Sdk.Server/Crypto/ICryptoProvider.cs` | 9 |
| `Crypto/AlgorithmRegistry.cs` | `src/Ssdid.Sdk.Server/Crypto/AlgorithmRegistry.cs` | 67 |
| `Crypto/CryptoProviderFactory.cs` | `src/Ssdid.Sdk.Server/Crypto/CryptoProviderFactory.cs` | 46 |
| `Crypto/Providers/Ed25519Provider.cs` | `src/Ssdid.Sdk.Server/Crypto/Providers/Ed25519Provider.cs` | 47 |
| `Crypto/Providers/EcdsaProvider.cs` | `src/Ssdid.Sdk.Server/Crypto/Providers/EcdsaProvider.cs` | 77 |
| **New** | `src/Ssdid.Sdk.Server/SsdidServerOptions.cs` | ~30 |
| **New** | `src/Ssdid.Sdk.Server/ServiceCollectionExtensions.cs` | ~60 |
| **New** | `src/Ssdid.Sdk.Server/SsdidError.cs` | ~20 |
| **New** | `src/Ssdid.Sdk.Server/Result.cs` | ~20 |

### PqcNist Package (Ssdid.Sdk.Server.PqcNist)

| Source | Destination | Lines |
|---|---|---|
| `Crypto/Providers/MlDsaProvider.cs` | `src/Ssdid.Sdk.Server.PqcNist/Providers/MlDsaProvider.cs` | 66 |
| `Crypto/Providers/SlhDsaProvider.cs` | `src/Ssdid.Sdk.Server.PqcNist/Providers/SlhDsaProvider.cs` | 75 |
| **New** | `src/Ssdid.Sdk.Server.PqcNist/ServiceCollectionExtensions.cs` | ~15 |

### KazSign Package (Ssdid.Sdk.Server.KazSign)

| Source | Destination | Lines |
|---|---|---|
| `Crypto/Providers/KazSignProvider.cs` | `src/Ssdid.Sdk.Server.KazSign/Providers/KazSignProvider.cs` | 313 |
| `Crypto/Native/KazSign.cs` | `src/Ssdid.Sdk.Server.KazSign/Native/KazSign.cs` | 1122 |
| **New** | `src/Ssdid.Sdk.Server.KazSign/ServiceCollectionExtensions.cs` | ~15 |

---

## Chunk 1: Scaffold Repo + Core Package Structure

### Task 1: Create repo and solution

- [ ] **Step 1: Create repo directory**

```bash
mkdir -p ~/Workspace/ssdid-sdk-dotnet
cd ~/Workspace/ssdid-sdk-dotnet
git init
```

- [ ] **Step 2: Create solution and projects**

```bash
dotnet new sln -n Ssdid.Sdk.Server

# Core package
dotnet new classlib -n Ssdid.Sdk.Server -o src/Ssdid.Sdk.Server -f net10.0
dotnet sln add src/Ssdid.Sdk.Server

# PqcNist package
dotnet new classlib -n Ssdid.Sdk.Server.PqcNist -o src/Ssdid.Sdk.Server.PqcNist -f net10.0
dotnet sln add src/Ssdid.Sdk.Server.PqcNist

# KazSign package
dotnet new classlib -n Ssdid.Sdk.Server.KazSign -o src/Ssdid.Sdk.Server.KazSign -f net10.0
dotnet sln add src/Ssdid.Sdk.Server.KazSign

# Test projects
dotnet new xunit -n Ssdid.Sdk.Server.Tests -o tests/Ssdid.Sdk.Server.Tests -f net10.0
dotnet sln add tests/Ssdid.Sdk.Server.Tests

dotnet new xunit -n Ssdid.Sdk.Server.PqcNist.Tests -o tests/Ssdid.Sdk.Server.PqcNist.Tests -f net10.0
dotnet sln add tests/Ssdid.Sdk.Server.PqcNist.Tests

dotnet new xunit -n Ssdid.Sdk.Server.KazSign.Tests -o tests/Ssdid.Sdk.Server.KazSign.Tests -f net10.0
dotnet sln add tests/Ssdid.Sdk.Server.KazSign.Tests
```

- [ ] **Step 3: Add project references**

```bash
# PqcNist depends on Core
dotnet add src/Ssdid.Sdk.Server.PqcNist reference src/Ssdid.Sdk.Server

# KazSign depends on Core
dotnet add src/Ssdid.Sdk.Server.KazSign reference src/Ssdid.Sdk.Server

# Test projects reference their packages
dotnet add tests/Ssdid.Sdk.Server.Tests reference src/Ssdid.Sdk.Server
dotnet add tests/Ssdid.Sdk.Server.PqcNist.Tests reference src/Ssdid.Sdk.Server.PqcNist
dotnet add tests/Ssdid.Sdk.Server.KazSign.Tests reference src/Ssdid.Sdk.Server.KazSign
```

- [ ] **Step 4: Add NuGet dependencies to Core**

```bash
cd src/Ssdid.Sdk.Server
dotnet add package BouncyCastle.Cryptography
dotnet add package StackExchange.Redis
dotnet add package Microsoft.Extensions.DependencyInjection.Abstractions
dotnet add package Microsoft.Extensions.Hosting.Abstractions
dotnet add package Microsoft.Extensions.Logging.Abstractions
dotnet add package Microsoft.Extensions.Caching.Abstractions
dotnet add package Microsoft.Extensions.Options
dotnet add package Microsoft.Extensions.Http
```

- [ ] **Step 5: Add NuGet dependencies to PqcNist**

PqcNist needs BouncyCastle (already transitively available from Core, but declare explicitly):
```bash
cd src/Ssdid.Sdk.Server.PqcNist
dotnet add package BouncyCastle.Cryptography
```

- [ ] **Step 6: Create directory structure**

```bash
cd ~/Workspace/ssdid-sdk-dotnet

# Core
mkdir -p src/Ssdid.Sdk.Server/{Auth,Crypto/Providers,Encoding,Identity,Registry,Session/InMemory,Session/Redis,Registration}

# PqcNist
mkdir -p src/Ssdid.Sdk.Server.PqcNist/Providers

# KazSign
mkdir -p src/Ssdid.Sdk.Server.KazSign/{Providers,Native}

# Tests
mkdir -p tests/Ssdid.Sdk.Server.Tests/{Auth,Crypto/Providers,Encoding,Identity,Registry,Session}
mkdir -p tests/Ssdid.Sdk.Server.PqcNist.Tests/Providers
mkdir -p tests/Ssdid.Sdk.Server.KazSign.Tests/Providers
```

- [ ] **Step 7: Delete placeholder Class1.cs files**

```bash
find . -name "Class1.cs" -delete
```

- [ ] **Step 8: Create .gitignore**

```bash
cat > .gitignore << 'EOF'
bin/
obj/
.vs/
*.user
*.suo
.idea/
*.DotSettings.user
EOF
```

- [ ] **Step 9: Build to verify scaffold**

```bash
dotnet build
```

- [ ] **Step 10: Initial commit**

```bash
git add -A
git commit -m "chore: scaffold Ssdid.Sdk.Server solution with 3 packages + tests"
```

---

### Task 2: Create Result<T> and SsdidError types

**Files:**
- Create: `src/Ssdid.Sdk.Server/Result.cs`
- Create: `src/Ssdid.Sdk.Server/SsdidError.cs`

- [ ] **Step 1: Create SsdidError**

```csharp
// src/Ssdid.Sdk.Server/SsdidError.cs
namespace Ssdid.Sdk.Server;

/// <summary>
/// Represents an SSDID protocol error.
/// </summary>
public record SsdidError(string Code, string Message, int? HttpStatus = null)
{
    public static SsdidError BadRequest(string message) => new("bad_request", message, 400);
    public static SsdidError NotFound(string message) => new("not_found", message, 404);
    public static SsdidError Unauthorized(string message) => new("unauthorized", message, 401);
    public static SsdidError Forbidden(string message) => new("forbidden", message, 403);
    public static SsdidError Conflict(string message) => new("conflict", message, 409);
    public static SsdidError Internal(string message) => new("internal", message, 500);
}
```

- [ ] **Step 2: Create Result<T>**

```csharp
// src/Ssdid.Sdk.Server/Result.cs
namespace Ssdid.Sdk.Server;

/// <summary>
/// Result monad for SSDID operations. No dependency on ASP.NET Core.
/// </summary>
public readonly struct Result<T>
{
    public T? Value { get; }
    public SsdidError? Error { get; }
    public bool IsSuccess => Error is null;

    private Result(T value) { Value = value; Error = null; }
    private Result(SsdidError error) { Value = default; Error = error; }

    public static implicit operator Result<T>(T value) => new(value);
    public static implicit operator Result<T>(SsdidError error) => new(error);

    public TResult Match<TResult>(Func<T, TResult> success, Func<SsdidError, TResult> failure) =>
        IsSuccess ? success(Value!) : failure(Error!);

    public async Task<TResult> Match<TResult>(Func<T, Task<TResult>> success, Func<SsdidError, Task<TResult>> failure) =>
        IsSuccess ? await success(Value!) : await failure(Error!);
}
```

- [ ] **Step 3: Build**

```bash
dotnet build src/Ssdid.Sdk.Server
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add Result<T> and SsdidError types"
```

---

## Chunk 2: Extract Encoding + Crypto Layer

### Task 3: Extract SsdidEncoding (was SsdidCrypto)

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/SsdidCrypto.cs`
**Destination:** `src/Ssdid.Sdk.Server/Encoding/SsdidEncoding.cs`

- [ ] **Step 1: Copy and re-namespace**

Copy `SsdidCrypto.cs` to `src/Ssdid.Sdk.Server/Encoding/SsdidEncoding.cs`. Change:
- Namespace: `SsdidDrive.Api.Ssdid` → `Ssdid.Sdk.Server.Encoding`
- Class name: `SsdidCrypto` → `SsdidEncoding`

- [ ] **Step 2: Port tests**

Copy `tests/SsdidDrive.Api.Tests/Ssdid/SsdidCryptoTests.cs` to `tests/Ssdid.Sdk.Server.Tests/Encoding/SsdidEncodingTests.cs`. Update namespace and class references.

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/Ssdid.Sdk.Server.Tests
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: extract SsdidEncoding (base64url, multibase, SHA3, canonical JSON)"
```

---

### Task 4: Extract ICryptoProvider + AlgorithmRegistry + CryptoProviderFactory

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Crypto/{ICryptoProvider,AlgorithmRegistry,CryptoProviderFactory}.cs`

- [ ] **Step 1: Copy and re-namespace all 3 files**

- `ICryptoProvider.cs` → `src/Ssdid.Sdk.Server/Crypto/ICryptoProvider.cs` (namespace `Ssdid.Sdk.Server.Crypto`)
- `AlgorithmRegistry.cs` → `src/Ssdid.Sdk.Server/Crypto/AlgorithmRegistry.cs`
- `CryptoProviderFactory.cs` → `src/Ssdid.Sdk.Server/Crypto/CryptoProviderFactory.cs`

- [ ] **Step 2: Port tests**

- `AlgorithmRegistryTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Crypto/AlgorithmRegistryTests.cs`
- `CryptoProviderFactoryTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Crypto/CryptoProviderFactoryTests.cs`

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/Ssdid.Sdk.Server.Tests
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: extract ICryptoProvider, AlgorithmRegistry, CryptoProviderFactory"
```

---

### Task 5: Extract Ed25519 + ECDSA providers

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Crypto/Providers/{Ed25519Provider,EcdsaProvider}.cs`

- [ ] **Step 1: Copy and re-namespace**

- `Ed25519Provider.cs` → `src/Ssdid.Sdk.Server/Crypto/Providers/Ed25519Provider.cs` (namespace `Ssdid.Sdk.Server.Crypto.Providers`)
- `EcdsaProvider.cs` → `src/Ssdid.Sdk.Server/Crypto/Providers/EcdsaProvider.cs`

- [ ] **Step 2: Port tests**

- `Ed25519ProviderTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Crypto/Providers/Ed25519ProviderTests.cs`
- `EcdsaProviderTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Crypto/Providers/EcdsaProviderTests.cs`

- [ ] **Step 3: Run tests**

```bash
dotnet test tests/Ssdid.Sdk.Server.Tests
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: extract Ed25519 and ECDSA crypto providers"
```

---

## Chunk 3: Extract Identity + Registry + Session

### Task 6: Extract SsdidIdentity

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/SsdidIdentity.cs`

- [ ] **Step 1: Copy, re-namespace, update references**

Copy to `src/Ssdid.Sdk.Server/Identity/SsdidIdentity.cs`. Change:
- Namespace: `Ssdid.Sdk.Server.Identity`
- Reference `SsdidCrypto` → `SsdidEncoding`
- Reference `CryptoProviderFactory` → `Ssdid.Sdk.Server.Crypto.CryptoProviderFactory`

- [ ] **Step 2: Port tests**

Copy `SsdidIdentityTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Identity/SsdidIdentityTests.cs`

- [ ] **Step 3: Run tests + commit**

```bash
dotnet test tests/Ssdid.Sdk.Server.Tests
git add -A && git commit -m "feat: extract SsdidIdentity (server DID, DID Document builder)"
```

---

### Task 7: Extract RegistryClient

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/RegistryClient.cs`

- [ ] **Step 1: Copy, re-namespace**

Copy to `src/Ssdid.Sdk.Server/Registry/RegistryClient.cs`. Namespace: `Ssdid.Sdk.Server.Registry`.

- [ ] **Step 2: Run tests + commit**

```bash
dotnet build src/Ssdid.Sdk.Server
git add -A && git commit -m "feat: extract RegistryClient (DID resolution + registration)"
```

---

### Task 8: Extract Session layer (interfaces + InMemory + Redis)

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/{ISessionStore,ISseNotificationBus,SessionStoreOptions,SessionStore,RedisSessionStore}.cs`

- [ ] **Step 1: Copy interfaces and options**

- `ISessionStore.cs` → `src/Ssdid.Sdk.Server/Session/ISessionStore.cs`
- `ISseNotificationBus.cs` → `src/Ssdid.Sdk.Server/Session/ISseNotificationBus.cs`
- `SessionStoreOptions.cs` → `src/Ssdid.Sdk.Server/Session/SessionStoreOptions.cs`

All namespace: `Ssdid.Sdk.Server.Session`

- [ ] **Step 2: Copy InMemory implementation**

`SessionStore.cs` → `src/Ssdid.Sdk.Server/Session/InMemory/InMemorySessionStore.cs`
- Rename class `SessionStore` → `InMemorySessionStore`
- Namespace: `Ssdid.Sdk.Server.Session.InMemory`

- [ ] **Step 3: Copy Redis implementation**

`RedisSessionStore.cs` → `src/Ssdid.Sdk.Server/Session/Redis/RedisSessionStore.cs`
- Namespace: `Ssdid.Sdk.Server.Session.Redis`

- [ ] **Step 4: Port tests**

`SessionStoreTests.cs` → `tests/Ssdid.Sdk.Server.Tests/Session/InMemorySessionStoreTests.cs`
- Update class references

- [ ] **Step 5: Run tests + commit**

```bash
dotnet test tests/Ssdid.Sdk.Server.Tests
git add -A && git commit -m "feat: extract session layer (ISessionStore, InMemory, Redis)"
```

---

## Chunk 4: Extract Auth Service + Server Registration

### Task 9: Extract SsdidAuthService

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/SsdidAuthService.cs`

This is the most complex extraction. The auth service has some app-specific code mixed in.

- [ ] **Step 1: Copy to SDK**

Copy to `src/Ssdid.Sdk.Server/Auth/SsdidAuthService.cs`. Namespace: `Ssdid.Sdk.Server.Auth`.

- [ ] **Step 2: Remove app-specific dependencies**

The ssdid-drive version references:
- `IConfiguration` for `Ssdid:PreviousIdentities` → replace with `SsdidServerOptions.PreviousIdentities` (string array)
- `AppError` → replace with `SsdidError`
- `Result<T>` → use SDK's `Result<T>`

Keep:
- `SsdidIdentity`, `ISessionStore`, `RegistryClient`, `CryptoProviderFactory` dependencies
- `HandleRegister()`, `HandleVerifyResponse()`, `VerifyCredential()`, `CreateAuthenticatedSession()`

- [ ] **Step 3: Extract response DTOs**

Create separate files in `Auth/`:
- `RegisterResponse.cs` — `record RegisterResponse(string Challenge, string ServerDid, string ServerKeyId, string ServerSignature)`
- `VerifyResponse.cs` — `record VerifyResponse(JsonElement Credential, string Did)`
- `AuthenticateResponse.cs` — `record AuthenticateResponse(string SessionToken, string Did, string ServerDid, string ServerKeyId, string ServerSignature)`

- [ ] **Step 4: Build + commit**

```bash
dotnet build src/Ssdid.Sdk.Server
git add -A && git commit -m "feat: extract SsdidAuthService (challenge-response, VC issuance/verification)"
```

---

### Task 10: Extract ServerRegistrationService

**Source:** `~/Workspace/ssdid-drive/src/SsdidDrive.Api/Ssdid/ServerRegistrationService.cs`

- [ ] **Step 1: Copy and re-namespace**

Copy to `src/Ssdid.Sdk.Server/Registration/ServerRegistrationService.cs`. Namespace: `Ssdid.Sdk.Server.Registration`.

- [ ] **Step 2: Build + commit**

```bash
dotnet build src/Ssdid.Sdk.Server
git add -A && git commit -m "feat: extract ServerRegistrationService (startup DID registration)"
```

---

## Chunk 5: DI Extensions + Configuration

### Task 11: Create SsdidServerOptions and AddSsdidServer()

- [ ] **Step 1: Create options class**

```csharp
// src/Ssdid.Sdk.Server/SsdidServerOptions.cs
namespace Ssdid.Sdk.Server;

public class SsdidServerOptions
{
    public string RegistryUrl { get; set; } = "https://registry.ssdid.my";
    public string IdentityPath { get; set; } = "data/server-identity.json";
    public string Algorithm { get; set; } = "Ed25519VerificationKey2020";
    public string[] PreviousIdentities { get; set; } = [];
    public Session.SessionStoreOptions Sessions { get; set; } = new();
}
```

- [ ] **Step 2: Create AddSsdidServer extension**

```csharp
// src/Ssdid.Sdk.Server/ServiceCollectionExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Auth;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.Crypto.Providers;
using Ssdid.Sdk.Server.Encoding;
using Ssdid.Sdk.Server.Identity;
using Ssdid.Sdk.Server.Registry;
using Ssdid.Sdk.Server.Registration;
using Ssdid.Sdk.Server.Session;
using Ssdid.Sdk.Server.Session.InMemory;

namespace Ssdid.Sdk.Server;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddSsdidServer(
        this IServiceCollection services,
        Action<SsdidServerOptions>? configure = null)
    {
        var options = new SsdidServerOptions();
        configure?.Invoke(options);

        services.AddSingleton(Microsoft.Extensions.Options.Options.Create(options));
        services.AddSingleton(Microsoft.Extensions.Options.Options.Create(options.Sessions));

        // Crypto providers (Ed25519 + ECDSA built-in)
        services.AddSingleton<ICryptoProvider, Ed25519Provider>();
        services.AddSingleton<ICryptoProvider, EcdsaProvider>();
        services.AddSingleton<CryptoProviderFactory>();

        // Identity
        services.AddSingleton<SsdidIdentity>(sp =>
        {
            var cryptoFactory = sp.GetRequiredService<CryptoProviderFactory>();
            return SsdidIdentity.LoadOrCreate(options.IdentityPath, options.Algorithm, cryptoFactory);
        });

        // Registry client
        services.AddHttpClient<RegistryClient>(client =>
        {
            client.BaseAddress = new Uri(options.RegistryUrl);
            client.Timeout = TimeSpan.FromSeconds(15);
        });

        // Session store (in-memory default)
        services.AddSingleton<InMemorySessionStore>();
        services.AddSingleton<ISessionStore>(sp => sp.GetRequiredService<InMemorySessionStore>());
        services.AddSingleton<ISseNotificationBus>(sp => sp.GetRequiredService<InMemorySessionStore>());

        // Auth service
        services.AddScoped<SsdidAuthService>();

        // Server DID registration on startup
        services.AddHostedService<ServerRegistrationService>();

        return services;
    }

    /// <summary>
    /// Replace the default in-memory session store with Redis.
    /// </summary>
    public static IServiceCollection AddSsdidRedisSessionStore(
        this IServiceCollection services,
        string connectionString)
    {
        // Remove in-memory registrations
        // Add Redis implementation
        // (Implementation details depend on exact Redis setup)
        return services;
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
dotnet build src/Ssdid.Sdk.Server
git add -A && git commit -m "feat: add SsdidServerOptions and AddSsdidServer() DI extension"
```

---

### Task 12: Create AddSsdidPqcNist() extension

- [ ] **Step 1: Copy ML-DSA and SLH-DSA providers**

- `MlDsaProvider.cs` → `src/Ssdid.Sdk.Server.PqcNist/Providers/MlDsaProvider.cs` (namespace `Ssdid.Sdk.Server.PqcNist.Providers`)
- `SlhDsaProvider.cs` → `src/Ssdid.Sdk.Server.PqcNist/Providers/SlhDsaProvider.cs`

- [ ] **Step 2: Create extension method**

```csharp
// src/Ssdid.Sdk.Server.PqcNist/ServiceCollectionExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.PqcNist.Providers;

namespace Ssdid.Sdk.Server.PqcNist;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddSsdidPqcNist(this IServiceCollection services)
    {
        services.AddSingleton<ICryptoProvider, MlDsaProvider>();
        services.AddSingleton<ICryptoProvider, SlhDsaProvider>();
        return services;
    }
}
```

- [ ] **Step 3: Port tests + build**

Port `MlDsaProviderTests.cs` and `SlhDsaProviderTests.cs` to `tests/Ssdid.Sdk.Server.PqcNist.Tests/Providers/`.

```bash
dotnet build && dotnet test tests/Ssdid.Sdk.Server.PqcNist.Tests
git add -A && git commit -m "feat: add Ssdid.Sdk.Server.PqcNist package (ML-DSA, SLH-DSA)"
```

---

### Task 13: Create AddSsdidKazSign() extension

- [ ] **Step 1: Copy KazSign provider + native P/Invoke**

- `KazSignProvider.cs` → `src/Ssdid.Sdk.Server.KazSign/Providers/KazSignProvider.cs` (namespace `Ssdid.Sdk.Server.KazSign.Providers`)
- `KazSign.cs` (Native) → `src/Ssdid.Sdk.Server.KazSign/Native/KazSign.cs` (namespace `Ssdid.Sdk.Server.KazSign.Native`)

- [ ] **Step 2: Create extension method**

```csharp
// src/Ssdid.Sdk.Server.KazSign/ServiceCollectionExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using Ssdid.Sdk.Server.Crypto;
using Ssdid.Sdk.Server.KazSign.Providers;

namespace Ssdid.Sdk.Server.KazSign;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddSsdidKazSign(this IServiceCollection services)
    {
        services.AddSingleton<ICryptoProvider, KazSignProvider>();
        return services;
    }
}
```

- [ ] **Step 3: Port tests + build**

Port `KazSignProviderTests.cs` to `tests/Ssdid.Sdk.Server.KazSign.Tests/Providers/`.

```bash
dotnet build && dotnet test tests/Ssdid.Sdk.Server.KazSign.Tests
git add -A && git commit -m "feat: add Ssdid.Sdk.Server.KazSign package"
```

---

## Chunk 6: README + CI + Final Verification

### Task 14: Create README and CI

- [ ] **Step 1: Create README.md**

Include: overview, installation (3 packages), quick start, consumer API example, package structure.

- [ ] **Step 2: Create CI workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      - name: Build
        run: dotnet build -c Release
      - name: Test
        run: dotnet test -c Release --no-build
```

- [ ] **Step 3: Create LICENSE**

MIT license file.

- [ ] **Step 4: Run full test suite**

```bash
dotnet test
```

- [ ] **Step 5: Commit + push**

```bash
git add -A && git commit -m "docs: add README, CI workflow, and LICENSE"
git remote add origin https://github.com/amiryahaya/ssdid-sdk-dotnet.git
git push -u origin main
```

---

### Task 15: Update ssdid-drive to consume SDK

**This task happens in the ssdid-drive repo after the SDK is published/available.**

- [ ] **Step 1: Add project reference or NuGet reference**

In `ssdid-drive/src/SsdidDrive.Api/SsdidDrive.Api.csproj`, either:
- Local path reference: `<ProjectReference Include="../../../ssdid-sdk-dotnet/src/Ssdid.Sdk.Server/Ssdid.Sdk.Server.csproj" />`
- Or git submodule + path reference

- [ ] **Step 2: Replace inline code with SDK**

In `Program.cs`, replace individual service registrations with:
```csharp
builder.Services.AddSsdidServer(options => {
    options.RegistryUrl = builder.Configuration["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
    options.IdentityPath = "data/server-identity.json";
    options.Algorithm = builder.Configuration["Ssdid:Algorithm"] ?? "KazSignVerificationKey2024";
});
builder.Services.AddSsdidPqcNist();
builder.Services.AddSsdidKazSign();
```

- [ ] **Step 3: Delete extracted files from ssdid-drive**

Remove `src/SsdidDrive.Api/Ssdid/` and `src/SsdidDrive.Api/Crypto/` folders. Update `using` statements in endpoint files to reference new SDK namespaces.

- [ ] **Step 4: Run ssdid-drive tests**

```bash
dotnet test tests/SsdidDrive.Api.Tests/
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: replace inline SSDID code with Ssdid.Sdk.Server SDK"
```

---

## Implementation Order & Dependencies

```
Task 1:  Scaffold repo + solution                    ──┐
Task 2:  Result<T> + SsdidError                       ──┼── Chunk 1 (foundation)
                                                        │
Task 3:  SsdidEncoding                                ──┤
Task 4:  ICryptoProvider + AlgorithmRegistry + Factory ──┼── Chunk 2 (encoding + crypto)
Task 5:  Ed25519 + ECDSA providers                    ──┘
                                                        │
Task 6:  SsdidIdentity                                ──┤
Task 7:  RegistryClient                               ──┼── Chunk 3 (identity + session)
Task 8:  Session layer (interfaces + InMemory + Redis) ──┘
                                                        │
Task 9:  SsdidAuthService                             ──┤── Chunk 4 (auth core)
Task 10: ServerRegistrationService                    ──┘
                                                        │
Task 11: SsdidServerOptions + AddSsdidServer()        ──┤
Task 12: AddSsdidPqcNist() + ML-DSA/SLH-DSA          ──┼── Chunk 5 (DI + optional packages)
Task 13: AddSsdidKazSign() + KazSign                  ──┘
                                                        │
Task 14: README + CI + LICENSE                        ──┤── Chunk 6 (docs + integration)
Task 15: Update ssdid-drive to consume SDK            ──┘
```

All tasks are sequential — each depends on the previous. Tasks 12 and 13 can run in parallel.
