# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SsdidDrive is an ASP.NET Core 10 (.NET 10) Web API for a secure file-sharing platform using SSDID (Self-Sovereign Digital Identity) authentication. There are no passwords or OAuth — authentication is purely DID-based challenge-response with Verifiable Credentials, supporting 19 post-quantum and classical algorithms.

## Build & Run Commands

```bash
# Start PostgreSQL + Redis (required before running the API)
podman compose up -d

# Build
dotnet build src/SsdidDrive.Api

# Run (auto-migrates DB in Development)
dotnet run --project src/SsdidDrive.Api

# Run tests (when test projects exist)
dotnet test

# Add a new EF Core migration
dotnet ef migrations add <Name> --project src/SsdidDrive.Api

# Apply migrations manually
dotnet ef database update --project src/SsdidDrive.Api
```

## Architecture

**Single-project solution** at `src/SsdidDrive.Api/` using Minimal APIs with vertical slice (feature-based) organization.

### Key Directories

- `Features/` — Vertical slices. Each feature folder (Auth, Users, Health) contains a `*Feature.cs` that maps the route group, plus individual endpoint files (one class per endpoint).
- `Ssdid/` — Core SSDID identity and authentication layer: encoding utilities (`SsdidCrypto`), server identity management (`SsdidIdentity`), auth service (`SsdidAuthService`), in-memory session store (`SessionStore`), and DID registry client (`RegistryClient`).
- `Crypto/` — Multi-algorithm cryptography: `ICryptoProvider` strategy interface, `AlgorithmRegistry` (W3C type mappings), `CryptoProviderFactory` (DI-based dispatch), and `Providers/` with 5 family implementations (Ed25519, ECDSA, ML-DSA, SLH-DSA, KAZ-Sign). `Native/KazSign.cs` is the vendored P/Invoke wrapper.
- `Common/` — Cross-cutting: `Result<T>` monad for error handling, `AppError` for typed RFC 7807 problem responses, `CurrentUserAccessor` (scoped, populated by auth middleware).
- `Data/` — EF Core: `AppDbContext`, entity classes, migrations.
- `Middleware/` — `SsdidAuthMiddleware` validates Bearer tokens against `SessionStore`, loads the `User` from DB, and populates `CurrentUserAccessor`.

### Authentication Flow

1. Client calls `POST /api/auth/ssdid/register` with their DID — server resolves it via the SSDID Registry, returns a signed challenge.
2. Client signs the challenge and calls `POST /api/auth/ssdid/register/verify` — server verifies signature, issues a Verifiable Credential (W3C VC format).
3. Client presents the VC to `POST /api/auth/ssdid/authenticate` — server verifies offline, creates an in-memory session, returns a Bearer token.
4. All `/api/*` endpoints (except the auth endpoints above) require the Bearer token via `SsdidAuthMiddleware`.

### Conventions

- **API JSON**: snake_case (configured globally in `Program.cs`). Verifiable Credentials use camelCase to match W3C spec — they are serialized to `JsonElement` to bypass the global policy.
- **Error responses**: RFC 7807 Problem Details everywhere. Use `AppError` factory methods → `.ToProblemResult()`.
- **Result pattern**: Endpoints return `Result<T>` from service methods, matched with `.Match(ok => ..., err => ...)`.
- **Endpoint pattern**: Each endpoint is a static class with a `Map(RouteGroupBuilder)` method and a private `Handle` method.
- **Database**: PostgreSQL 17 via EF Core with Npgsql. Auto-migrates in Development mode. Tables use lowercase snake_case names.
- **Crypto**: Strategy pattern via `ICryptoProvider` with 5 family providers. Ed25519 uses BouncyCastle; ECDSA, ML-DSA, SLH-DSA use native .NET 10 (`System.Security.Cryptography`); KAZ-Sign uses vendored P/Invoke (`libkazsign`). `AlgorithmRegistry` maps 19 W3C verification method type strings to provider families. `CryptoProviderFactory` dispatches operations by type. ML-DSA/SLH-DSA are `[Experimental]` (SYSLIB5006 suppressed).
- **Server identity**: Persists to `data/server-identity.json` (gitignored — contains private key). Auto-generated on first run. Algorithm configurable via `Ssdid:Algorithm` in `appsettings.json` (default: `KazSignVerificationKey2024`).
- **Sessions**: Redis-backed via `RedisSessionStore` when `ConnectionStrings:Redis` is configured (default in `appsettings.json`); falls back to in-memory `SessionStore` when Redis connection string is empty. Redis store uses sliding expiration (1h sessions, 5m challenges), graceful degradation on Redis failures, and `SCAN`-based active session/challenge counting for admin metrics. SSE completion uses Redis pub/sub for cross-instance notification.

### Database Entities

- `User` — identified by DID, stores client-encrypted key material (zero-knowledge), belongs to optional primary `Tenant`
- `Tenant` — organizational unit with unique slug
- `UserTenant` — many-to-many with role (Owner/Admin/Member)
