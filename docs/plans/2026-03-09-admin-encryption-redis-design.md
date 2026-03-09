# Admin Portal, File Encryption Layer & Distributed Sessions — Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create the implementation plan from this design.

**Goal:** Add a system superadmin portal, wire end-to-end file encryption across all client platforms, and harden Redis-backed distributed sessions.

---

## 1. Admin Portal

### Architecture
- `clients/admin/` — React SPA (Vite + TypeScript + Tailwind + Zustand)
- Served at `/admin/` by ASP.NET Core static files middleware
- Auth: SSDID DID-based login (same flow as regular users), backend enforces `SystemRole` on `User` entity

### User Entity Change
- Add `SystemRole` column to `User` (nullable enum: `SuperAdmin`). First registered user or env-var-configured DID gets SuperAdmin.

### New Backend Endpoints (`/api/admin/*`)
- `GET /api/admin/stats` — dashboard overview (user count, tenant count, active sessions, storage used)
- `GET /api/admin/users` — list all users with pagination/search
- `PATCH /api/admin/users/{id}` — suspend/activate user
- `GET /api/admin/tenants` — list all tenants with pagination/search
- `POST /api/admin/tenants` — create tenant
- `PATCH /api/admin/tenants/{id}` — update tenant (name, quota, disable)
- `GET /api/admin/tenants/{id}/members` — list tenant members
- `GET /api/admin/audit-log` — recent admin actions

### Admin Authorization
- Middleware checks `User.SystemRole == SuperAdmin` for all `/api/admin/*` routes.

### UI Pages
- Dashboard (stats cards, recent activity)
- Users (table with search, suspend/activate actions)
- Tenants (table with create, edit quota, disable)
- Tenant detail (members, storage usage)
- Audit log

---

## 2. File Encryption Layer

### Backend API Additions
- `POST /api/me/keys/public` — publish user's KEM public key (separate from sign key)
- `GET /api/users/{id}/kem-public-key` — fetch another user's KEM public key (for sharing)
- `POST /api/folders/{id}/rotate-key` — trigger folder key rotation (re-encrypts folder key for all members)
- `GET /api/folders/{id}/key` — get caller's encrypted copy of the folder key

### Client-Side Crypto Flow (all platforms)
1. **Registration** — Client generates KEM key pair (KAZ-KEM or ML-KEM), publishes public key to server, stores private key locally (encrypted with master key derived from passphrase via HKDF)
2. **Create folder** — Client generates random AES-256-GCM folder key, encrypts it with own KEM public key, uploads encrypted folder key
3. **Upload file** — Client derives per-file key from folder key via HKDF(folder_key, file_id), encrypts file with AES-256-GCM, uploads ciphertext + nonce
4. **Download file** — Client fetches encrypted folder key, decrypts with KEM private key, derives file key, decrypts file
5. **Share folder** — Client fetches recipient's KEM public key, encapsulates folder key for recipient, server stores re-encrypted key on Share entity

### Key Derivation
- Master key: HKDF-SHA3-256(passphrase, salt) — stored encrypted in server (`encrypted_master_key` on User)
- Folder key: random 256-bit, encrypted per-user via KEM
- File key: HKDF-SHA3-256(folder_key, file_id) — deterministic, never stored

### Client Implementations
- **Desktop (Rust)** — `securesharing-crypto` crate has `symmetric.rs`, `ml_kem.rs`, `kaz_kem.rs`, `shamir.rs`. Wire into Tauri commands for encrypt/decrypt/key-exchange.
- **Android (Kotlin)** — `kazkem-release.aar` + `kazsign-release.aar` in `app/libs/`. Wire `CryptoManager`, `FileEncryptor`, `FileDecryptor`, `KeyEncapsulation`, `FolderKeyManager`.
- **iOS (Swift)** — `KazKemNative.xcframework` vendored. Wire through `FileProviderCore` module (`FPEncryptor`, `FPDecryptor`, `FPKeychainReader`).

---

## 3. Distributed Sessions — Redis

### Integration Testing
- Testcontainers for .NET to spin up Redis 7 container
- Test RedisSessionStore: create/consume challenges, create/validate/revoke sessions, TTL expiry, pub/sub for SSE
- Test auto-switch logic in Program.cs (Redis vs in-memory)
- Test atomic StringGetDelete for concurrent challenge consumption

### Production Hardening
- **Health check** — `IHealthCheck` for Redis, registered at `/health/redis`
- **Connection resilience** — `ConnectRetry`, `AbortOnConnectFail=false`, `ReconnectRetryPolicy`
- **Graceful fallback** — If Redis unreachable after startup, log errors, return 503 (don't crash)
- **Session metrics** — `GET /api/admin/sessions` returning active session/challenge counts (admin only)
- **Configuration** — Support connection string with options and Sentinel format

### Not In Scope
- Redis Cluster sharding
- Session replication across regions
- Cache warmup or preloading
