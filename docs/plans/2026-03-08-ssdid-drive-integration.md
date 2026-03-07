# SSDID Drive Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace SecureSharing's username/password auth with SSDID wallet-delegated authentication across all drive clients and the backend API, and wire up the file encryption layer.

**Architecture:** Drive clients delegate identity operations (registration, authentication, transaction signing) to the SSDID Wallet app. Desktop uses QR codes; mobile uses deep links. The backend issues challenges and verifies signatures/VCs using the SSDID Server SDK (already partially built). File encryption uses PQC KEM/KDF and is client-held (separate from identity auth).

**Tech Stack:** .NET 10 (backend), Kotlin/Compose (Android), Tauri v2/React/Rust (Desktop), Swift (iOS), PQC crypto (ML-DSA, ML-KEM, KAZ-Sign, KAZ-KEM)

---

## Current State

### What's Already Done
- Backend API (`SsdidDrive.Api`) has full SSDID auth: challenge-response, DID resolution, VC verification, session management
- Backend has 5 PQC crypto providers (Ed25519, ECDSA, ML-DSA, SLH-DSA, KAZ-Sign) with 191 tests
- Backend endpoints: `/api/auth/ssdid/register`, `/register/verify`, `/authenticate`, `/server-info`, `/logout`
- SSDID Wallet (`ssdid-wallet`) has: DID creation, QR scanning, deep link handling, VC storage, mutual auth flows
- Drive clients (Android, Desktop, iOS) copied and renamed but still have old SecureSharing auth (email/password, OIDC, WebAuthn)

### What Needs to Change
- Drive clients: Replace password-based auth with wallet-delegated auth
- Drive clients: Add QR code display (desktop) and deep link invocation (mobile) to trigger wallet
- Backend: Add file management endpoints (upload, download, share, folders)
- Backend: Add WebSocket/SSE for real-time challenge completion notifications
- All: Wire up file encryption (KEM encapsulation, folder keys, file encrypt/decrypt)

---

## Phase 1: Backend — File Management API

### Task 1.1: File & Folder Entities

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/FileEntity.cs`
- Create: `src/SsdidDrive.Api/Data/Entities/FolderEntity.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

**What to build:**
```csharp
// FolderEntity
public class FolderEntity
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public Guid? ParentFolderId { get; set; }
    public Guid OwnerId { get; set; }
    public Guid TenantId { get; set; }
    public byte[]? EncryptedFolderKey { get; set; }  // KEM-encapsulated folder key
    public string? KemAlgorithm { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public FolderEntity? ParentFolder { get; set; }
    public UserEntity Owner { get; set; } = null!;
    public TenantEntity Tenant { get; set; } = null!;
    public ICollection<FolderEntity> SubFolders { get; set; } = [];
    public ICollection<FileEntity> Files { get; set; } = [];
}

// FileEntity
public class FileEntity
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;      // encrypted filename
    public string ContentType { get; set; } = string.Empty;
    public long Size { get; set; }
    public string StoragePath { get; set; } = string.Empty; // path to encrypted blob
    public Guid FolderId { get; set; }
    public Guid UploadedById { get; set; }
    public byte[]? EncryptedFileKey { get; set; }  // file key encrypted with folder key
    public byte[]? Nonce { get; set; }              // AES-GCM nonce
    public string? EncryptionAlgorithm { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public FolderEntity Folder { get; set; } = null!;
    public UserEntity UploadedBy { get; set; } = null!;
}
```

**Steps:**
1. Create entity files with the above models
2. Add `DbSet<FolderEntity>` and `DbSet<FileEntity>` to `AppDbContext`
3. Configure relationships and indexes in `OnModelCreating`
4. Run `dotnet ef migrations add AddFilesAndFolders`
5. Commit: `feat(api): add File and Folder entities with KEM-encrypted keys`

### Task 1.2: Share Entity

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/ShareEntity.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

**What to build:**
```csharp
public class ShareEntity
{
    public Guid Id { get; set; }
    public Guid ResourceId { get; set; }        // file or folder ID
    public string ResourceType { get; set; } = string.Empty; // "file" or "folder"
    public Guid SharedById { get; set; }
    public Guid SharedWithId { get; set; }
    public string Permission { get; set; } = "read"; // read, write, admin
    public byte[]? EncryptedKey { get; set; }    // folder/file key re-encrypted for recipient
    public string? KemAlgorithm { get; set; }
    public DateTimeOffset? ExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public UserEntity SharedBy { get; set; } = null!;
    public UserEntity SharedWith { get; set; } = null!;
}
```

**Steps:**
1. Create entity, add DbSet, configure relationships
2. Add migration
3. Commit: `feat(api): add Share entity for encrypted key distribution`

### Task 1.3: Folder Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Folders/FolderFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Folders/CreateFolder.cs`
- Create: `src/SsdidDrive.Api/Features/Folders/ListFolders.cs`
- Create: `src/SsdidDrive.Api/Features/Folders/GetFolder.cs`
- Create: `src/SsdidDrive.Api/Features/Folders/DeleteFolder.cs`

**Endpoints:**
```
POST   /api/folders              — Create folder (with KEM-encapsulated folder key)
GET    /api/folders?parent_id=   — List folders (root if no parent)
GET    /api/folders/{id}         — Get folder details + encrypted key
DELETE /api/folders/{id}         — Delete folder (owner/admin only)
```

**Steps:**
1. Create each endpoint handler following existing feature pattern (see `Features/Auth/`)
2. Authorization: check tenant membership, folder ownership
3. Tests: create folder, list, get, delete, permission checks
4. Commit: `feat(api): add folder CRUD endpoints`

### Task 1.4: File Upload/Download Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Files/FileFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Files/UploadFile.cs`
- Create: `src/SsdidDrive.Api/Features/Files/DownloadFile.cs`
- Create: `src/SsdidDrive.Api/Features/Files/ListFiles.cs`
- Create: `src/SsdidDrive.Api/Features/Files/DeleteFile.cs`
- Create: `src/SsdidDrive.Api/Services/StorageService.cs`

**Endpoints:**
```
POST   /api/folders/{folderId}/files  — Upload encrypted file (multipart)
GET    /api/files/{id}/download       — Download encrypted blob
GET    /api/folders/{folderId}/files  — List files in folder
DELETE /api/files/{id}                — Delete file
```

**Storage:** Local filesystem initially (`data/files/{tenant}/{folder}/{file}`), abstracted behind `IStorageService` for future S3/Azure Blob.

**Steps:**
1. Create `IStorageService` interface and `LocalStorageService` implementation
2. Create upload endpoint (accept multipart, store blob, save metadata)
3. Create download endpoint (stream encrypted blob)
4. Create list and delete endpoints
5. Tests for each endpoint
6. Commit: `feat(api): add file upload/download with encrypted storage`

### Task 1.5: Share Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Shares/ShareFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Shares/CreateShare.cs`
- Create: `src/SsdidDrive.Api/Features/Shares/ListShares.cs`
- Create: `src/SsdidDrive.Api/Features/Shares/RevokeShare.cs`

**Endpoints:**
```
POST   /api/shares               — Share file/folder (include re-encrypted key for recipient)
GET    /api/shares/created       — List shares I created
GET    /api/shares/received      — List shares shared with me
DELETE /api/shares/{id}          — Revoke share
```

**Steps:**
1. Create share endpoints with KEM key re-encryption support
2. Tests
3. Commit: `feat(api): add sharing endpoints with encrypted key exchange`

---

## Phase 2: Backend — Real-Time Auth Notifications

### Task 2.1: SSE Endpoint for Auth Challenge Completion

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/AuthEvents.cs`
- Modify: `src/SsdidDrive.Api/Ssdid/SessionStore.cs`

**Why:** When desktop shows QR code, it needs to know when the wallet has completed the challenge. SSE (Server-Sent Events) is simpler than WebSocket for this one-way notification.

**What to build:**
```
GET /api/auth/ssdid/events?challenge_id={id}  — SSE stream, emits "authenticated" when wallet completes challenge
```

**Flow:**
1. Desktop calls `/register` or creates challenge → gets `challenge_id`
2. Desktop opens SSE connection to `/events?challenge_id={id}`
3. Wallet scans QR, signs challenge, calls `/register/verify` or `/authenticate`
4. Backend completes verification, notifies SSE listener
5. Desktop receives event with session token

**Steps:**
1. Add `TaskCompletionSource` map to `SessionStore` for pending challenges
2. Create SSE endpoint that awaits completion with timeout (5 min)
3. Modify verify/authenticate endpoints to signal completion
4. Tests
5. Commit: `feat(api): add SSE endpoint for real-time auth challenge completion`

---

## Phase 3: Desktop Client — SSDID Auth with QR

### Task 3.1: Remove Old Auth, Add QR Login Page

**Files:**
- Modify: `clients/desktop/src/pages/LoginPage.tsx`
- Delete: `clients/desktop/src/components/auth/PasskeyButton.tsx`
- Delete: `clients/desktop/src/components/auth/OidcProviderButtons.tsx`
- Create: `clients/desktop/src/components/auth/QrChallenge.tsx`
- Modify: `clients/desktop/src/stores/authStore.ts`

**What to build:**
Replace the email/password form with a QR code display:
1. On page load, call backend `/api/auth/ssdid/server-info` to get server DID
2. Call `/api/auth/ssdid/register` (or new `/api/auth/ssdid/challenge` endpoint) to get challenge
3. Generate QR code containing JSON payload:
   ```json
   {
     "server_url": "https://api.ssdid.my",
     "server_did": "did:ssdid:...",
     "action": "authenticate",
     "challenge_id": "..."
   }
   ```
4. Display QR code on screen
5. Open SSE connection to `/api/auth/ssdid/events?challenge_id=...`
6. When wallet scans and completes, SSE fires → store session token
7. Navigate to files page

**Steps:**
1. Remove OidcProviderButtons, PasskeyButton components
2. Create QrChallenge component using a QR code library (e.g., `qrcode.react`)
3. Update LoginPage to show QR code instead of form
4. Update authStore to support QR-based login flow
5. Add SSE listener hook
6. Keep "Register" as separate flow (first-time users scan QR → wallet does registration)
7. Commit: `feat(desktop): replace password auth with QR-based SSDID login`

### Task 3.2: Update Rust Backend for SSDID Auth

**Files:**
- Modify: `clients/desktop/src-tauri/src/services/auth_service.rs`
- Modify: `clients/desktop/src-tauri/src/services/api_client.rs`
- Modify: `clients/desktop/src-tauri/src/commands/auth.rs`
- Delete: `clients/desktop/src-tauri/src/services/webauthn_service.rs`
- Delete: `clients/desktop/src-tauri/src/services/oidc_service.rs`
- Delete: `clients/desktop/src-tauri/src/commands/webauthn.rs`
- Delete: `clients/desktop/src-tauri/src/commands/oidc.rs`
- Delete: `clients/desktop/src-tauri/src/commands/credentials.rs`

**What to change:**
1. Remove password-based login/register from AuthService
2. Remove WebAuthn and OIDC services entirely
3. Add new commands:
   - `get_server_info()` → server DID, challenge
   - `create_challenge(action)` → challenge_id, QR payload
   - `wait_for_auth(challenge_id)` → session token (via SSE)
   - `check_session()` → current session status
4. Store session token in platform keyring
5. Remove SessionKeys (no more client-side key encryption for auth)

**Steps:**
1. Strip old auth services
2. Implement new SSDID-aware auth commands
3. Update `lib.rs` to remove old command registrations
4. Commit: `refactor(desktop): strip old auth, add SSDID challenge commands`

### Task 3.3: Update Desktop Registration Flow

**Files:**
- Modify: `clients/desktop/src/pages/RegisterPage.tsx`
- Modify: `clients/desktop/src/pages/OnboardingPage.tsx`

**What to change:**
Registration for desktop means:
1. User doesn't have a wallet yet → show instructions to install ssdid-wallet
2. User has wallet → scan QR code (same as login, but `action: "register"`)
3. Wallet handles key generation, DID creation, and registration with service
4. Desktop receives session after wallet completes registration

**Steps:**
1. Simplify RegisterPage to QR-based registration
2. Add "Install SSDID Wallet" instructions for new users
3. Update OnboardingPage
4. Commit: `feat(desktop): QR-based registration flow`

---

## Phase 4: Android Drive Client — SSDID Auth with Deep Links

### Task 4.1: Remove Old Auth, Add Deep Link Auth

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginScreen.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LoginViewModel.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/AuthRepositoryImpl.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/remote/ApiService.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/OidcLoginViewModel.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/PasskeyLoginViewModel.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/OidcRepositoryImpl.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/WebAuthnRepositoryImpl.kt`

**What to build:**
Since both ssdid-drive mobile and ssdid-wallet are mobile apps on the same device, use deep links:

1. LoginScreen shows "Sign in with SSDID Wallet" button
2. Button launches deep link: `ssdid://authenticate?server_url=...&server_did=...&challenge_id=...&callback=ssdiddrive://auth/callback`
3. Wallet opens, shows challenge details, user approves
4. Wallet signs challenge, posts to backend, then deep links back: `ssdiddrive://auth/callback?session_token=...`
5. Drive app receives callback, stores session token, navigates to files

**Steps:**
1. Remove OIDC and WebAuthn ViewModels and repositories
2. Simplify LoginScreen to single "Sign in with SSDID Wallet" button
3. Update AuthRepository to use challenge-based auth
4. Add callback deep link handler in DeepLinkHandler
5. Update ApiService to use new SSDID endpoints
6. Remove AuthInterceptor password logic, keep token-based auth
7. Commit: `feat(android): replace password auth with SSDID wallet deep link flow`

### Task 4.2: Update Android Registration Flow

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/RegisterScreen.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/RegisterViewModel.kt`

**What to change:**
1. Registration = deep link to wallet with `action: "register"`
2. Wallet creates identity (if needed), registers with service, returns
3. Drive receives callback with session token

**Steps:**
1. Simplify RegisterScreen
2. Add "Install SSDID Wallet" flow for users without wallet
3. Commit: `feat(android): deep link registration with SSDID wallet`

### Task 4.3: Remove Client-Side Key Management from Drive

**Files:**
- Delete/simplify: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/KeyManager.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/RecoveryKeyManager.kt`
- Delete: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/ShamirSecretSharing.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/CryptoManager.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/LockScreen.kt`

**Why:** Identity keys live in the wallet, not the drive client. The drive client only needs file encryption keys (KEM/KDF for encrypting files). Remove identity key generation, password-based key derivation, Shamir secret sharing, and recovery key management.

**Keep:**
- `FileEncryptor.kt` / `FileDecryptor.kt` — file-level AES-GCM encryption
- `FolderKeyManager.kt` — folder key generation and KEM encapsulation
- `KeyEncapsulation.kt` — KEM operations for key wrapping
- KAZ-KEM and ML-KEM providers for file encryption

**Steps:**
1. Remove identity key management code
2. Remove Shamir secret sharing
3. Remove password-based KDF for auth keys
4. Simplify LockScreen (biometric only, no password unlock of identity keys)
5. Keep file encryption crypto intact
6. Commit: `refactor(android): remove identity key management, keep file encryption`

---

## Phase 5: iOS Client — SSDID Auth

### Task 5.1: iOS Auth with QR/Universal Links

**Files:**
- Modify files under `clients/ios/SsdidDrive/` (auth screens, view models)

**What to build:**
Same pattern as Desktop (QR) since iOS might be on a different device than wallet (iPad + phone).
Support both:
- QR code scanning (iPad/Mac → phone wallet)
- Universal links (same-device iPhone → wallet app)

**Steps:**
1. Replace password auth screens with QR display
2. Add universal link callback handler
3. Remove OIDC/WebAuthn code
4. Commit: `feat(ios): SSDID wallet auth via QR and universal links`

---

## Phase 6: File Encryption Integration

### Task 6.1: Desktop File Encryption with PQC KEM

**Files:**
- Modify: `clients/desktop/src-tauri/src/services/file_service.rs`
- Modify: `clients/desktop/src-tauri/src/services/crypto_service.rs`
- Modify: `clients/desktop/src-tauri/src/commands/files.rs`

**What to build:**
1. On folder creation: generate folder key, KEM-encapsulate with user's public key, send to backend
2. On file upload: generate file key, encrypt file with AES-256-GCM, encrypt file key with folder key, upload encrypted blob + metadata
3. On file download: fetch encrypted blob + keys, decrypt file key with folder key, decrypt file with file key
4. On share: re-encapsulate folder key with recipient's public key

**Steps:**
1. Implement folder key generation using ML-KEM or KAZ-KEM
2. Implement file encryption pipeline (encrypt → upload)
3. Implement file decryption pipeline (download → decrypt)
4. Wire up to UI (upload progress, download progress already exist)
5. Commit: `feat(desktop): PQC file encryption with KEM key wrapping`

### Task 6.2: Android File Encryption with PQC KEM

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/FileEncryptor.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/FileDecryptor.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/crypto/FolderKeyManager.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/FileRepositoryImpl.kt`

**What to build:**
Same as desktop but using the existing Android crypto providers (KazKemProvider, MlKemProvider).

**Steps:**
1. Wire FolderKeyManager to backend folder endpoints
2. Wire FileEncryptor/Decryptor to upload/download flow
3. Implement key re-encapsulation for sharing
4. Commit: `feat(android): PQC file encryption with KEM key wrapping`

### Task 6.3: iOS File Encryption

**Files:**
- Modify files under `clients/ios/SsdidDrive/` (crypto, file provider extension)

**Steps:**
1. Same pattern as Android/Desktop
2. Wire to FileProvider extension for system-level file integration
3. Commit: `feat(ios): PQC file encryption with KEM key wrapping`

---

## Phase 7: Housekeeping & CI

### Task 7.1: Update Solution File & GitIgnore

**Files:**
- Modify: `SsdidDrive.sln`
- Modify: `.gitignore`

**Steps:**
1. Add note in solution about client projects (not .NET, so not in .sln)
2. Update `.gitignore` for Android (`.gradle/`, `build/`), Desktop (`node_modules/`, `target/`, `dist/`), iOS (`build/`, `DerivedData/`)
3. Commit: `chore: update gitignore for client build artifacts`

### Task 7.2: Clean Up Deleted Old Files

**Files:**
- Delete: Old CI workflows (`.github/workflows/securesharing-*.yml`)
- Delete: Old root-level files (`AGENTS.md`, `Makefile`, `README.dev.md`, etc. — already marked as deleted in git)

**Steps:**
1. Stage deletions of old files shown in `git status`
2. Create new root `README.md` for ssdid-drive
3. Commit: `chore: remove old SecureSharing files, add ssdid-drive README`

### Task 7.3: CI Workflows

**Files:**
- Create: `.github/workflows/api-ci.yml`
- Create: `.github/workflows/android-ci.yml`
- Create: `.github/workflows/desktop-ci.yml`

**Steps:**
1. API CI: `dotnet build`, `dotnet test`, PostgreSQL service container
2. Android CI: Gradle build, unit tests
3. Desktop CI: `npm ci`, `npm run test:run`, `cargo test`
4. Commit: `ci: add CI workflows for API, Android, and Desktop`

---

## Dependency Graph

```
Phase 1 (Backend File API) ──────────────────────────────┐
                                                          │
Phase 2 (SSE for auth) ──┐                               │
                          │                               │
Phase 3 (Desktop auth) ──┤                               ├── Phase 6 (File encryption)
                          │                               │
Phase 4 (Android auth) ──┤                               │
                          │                               │
Phase 5 (iOS auth) ──────┘                               │
                                                          │
Phase 7 (Housekeeping) ──────────────────────────────────┘
```

- Phases 1 and 2 can run in parallel
- Phases 3, 4, 5 depend on Phase 2 (SSE)
- Phase 6 depends on Phase 1 (file endpoints)
- Phase 7 can run anytime

---

## Risk Notes

1. **Session store is in-memory** — fine for dev, needs Redis for production horizontal scaling
2. **File storage is local filesystem** — needs S3/Azure Blob for production
3. **Deep link callback security** — the `session_token` in callback URL needs to be short-lived and verified; consider using a one-time exchange code instead
4. **QR code payload size** — keep under 2KB for reliable scanning
5. **Wallet app availability** — need graceful handling when wallet app is not installed (show install instructions, app store link)
6. **iOS FileProvider** — complex integration; test thoroughly with Finder/Files app
