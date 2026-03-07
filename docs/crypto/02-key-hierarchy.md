# Key Hierarchy Specification

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-02

## 1. Overview

SecureSharing uses a hierarchical key management system where keys at each level protect keys at the level below. This design enables:
- Efficient key rotation
- Granular access control
- Secure sharing without re-encryption
- Zero-knowledge server architecture

## 2. Understanding DEK and KEK

### 2.1 Key Definitions

| Key | Full Name | What It Encrypts | Scope |
|-----|-----------|------------------|-------|
| **DEK** | Data Encryption Key | Actual file content | One per file |
| **KEK** | Key Encryption Key | DEKs (wraps/protects them) | One per folder |
| **MK** | Master Key | User's private keys | One per user |

### 2.2 Why Use a Key Hierarchy?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WITHOUT KEY HIERARCHY (Bad Design)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User's Master Key encrypts ALL files directly                              │
│                                                                              │
│  Problems:                                                                   │
│  ✗ Share one file = must share Master Key = access to EVERYTHING           │
│  ✗ Rotate key = re-encrypt ALL files (expensive, slow)                     │
│  ✗ Revoke access = re-encrypt ALL files                                    │
│  ✗ No granular permissions possible                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                    WITH KEY HIERARCHY (SecureSharing Design)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Master Key                                                                  │
│       │                                                                      │
│       ▼                                                                      │
│  KEK (per folder) ◄─── Share folder = share only this KEK                  │
│       │                                                                      │
│       ▼                                                                      │
│  DEK (per file) ◄───── Each file has unique encryption key                 │
│       │                                                                      │
│       ▼                                                                      │
│  File Content                                                                │
│                                                                              │
│  Benefits:                                                                   │
│  ✓ Share folder = share KEK only (Master Key stays private)                │
│  ✓ Share file = share DEK only (other files unaffected)                    │
│  ✓ Revoke access = rotate KEK, re-wrap DEKs (no file re-encryption)        │
│  ✓ Each file isolated (compromise one DEK ≠ compromise others)             │
│  ✓ Efficient key rotation at any level                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Concrete Example

```
User's Vault
│
├── Projects/                    ← KEK_projects
│   │
│   ├── Project-A/               ← KEK_project_a (wrapped by KEK_projects)
│   │   ├── report.pdf           ← DEK_1 (wrapped by KEK_project_a)
│   │   └── budget.xlsx          ← DEK_2 (wrapped by KEK_project_a)
│   │
│   └── Project-B/               ← KEK_project_b (wrapped by KEK_projects)
│       └── proposal.docx        ← DEK_3 (wrapped by KEK_project_b)
│
└── Personal/                    ← KEK_personal
    └── photo.jpg                ← DEK_4 (wrapped by KEK_personal)
```

### 2.4 Sharing Scenarios

| Action | Key Shared | What Recipient Can Access |
|--------|------------|---------------------------|
| Share `report.pdf` | DEK_1 only | Only that one file |
| Share `Project-A/` folder | KEK_project_a | All files in Project-A (current and future) |
| Share `Projects/` folder | KEK_projects | All files in Projects, Project-A, AND Project-B |

### 2.5 Key Wrapping Explained

"Wrapping" means encrypting a key with another key:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KEY WRAPPING PROCESS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  File Encryption (using DEK):                                               │
│  ─────────────────────────────                                              │
│  Plaintext File ──► AES-256-GCM(DEK) ──► Encrypted File (stored on server) │
│                                                                              │
│  DEK Protection (using KEK):                                                │
│  ───────────────────────────                                                │
│  DEK ──► AES-256-KWP(KEK) ──► Wrapped DEK (stored alongside file metadata) │
│                                                                              │
│  Decryption Process:                                                        │
│  ───────────────────                                                        │
│  1. Get KEK (unwrap using parent KEK or user's private key)                │
│  2. Unwrap DEK: DEK = AES-256-KWP-Decrypt(KEK, wrapped_dek)                │
│  3. Decrypt file: Plaintext = AES-256-GCM-Decrypt(DEK, ciphertext)         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.6 Revocation Efficiency

When revoking access, the key hierarchy allows efficient re-keying:

| Scenario | Without Hierarchy | With Hierarchy |
|----------|-------------------|----------------|
| Revoke user from 1 file | Re-encrypt file | Re-wrap DEK only |
| Revoke user from folder (100 files) | Re-encrypt 100 files | Rotate KEK, re-wrap 100 DEKs |
| Data touched | Entire file content | Only key metadata (tiny) |
| Time complexity | O(total file size) | O(number of files) |

**Key insight**: Re-wrapping a DEK (32 bytes) is instant. Re-encrypting a 1GB file takes significant time and I/O.

## 3. Key Hierarchy Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          KEY HIERARCHY                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  LEVEL 0: Authentication Secret                                     │
│  ═══════════════════════════════                                    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Auth Secret (from IdP)                                      │   │
│  │  ────────────────────────                                    │   │
│  │  • Passkey: PRF extension output (32 bytes)                  │   │
│  │  • Digital ID: Argon2id(vault_password) + cert binding       │   │
│  │  • OIDC: Argon2id(vault_password) + subject binding          │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                    │
│                                 │ HKDF derive                        │
│                                 ▼                                    │
│  LEVEL 1: Master Key (MK)                                           │
│  ════════════════════════                                           │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Master Key (256 bits)                                       │   │
│  │  ─────────────────────                                       │   │
│  │  • Generated randomly during registration                    │   │
│  │  • Encrypted by auth-derived key, stored on server           │   │
│  │  • Split into Shamir shares for recovery                     │   │
│  │  • NEVER transmitted in plaintext                            │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                    │
│                                 │ AES-256-GCM encrypt                │
│                                 ▼                                    │
│  LEVEL 2: User Key Pairs (PQC)                                      │
│  ═════════════════════════════                                      │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  User Cryptographic Keys                                     │   │
│  │  ───────────────────────                                     │   │
│  │                                                               │   │
│  │  Encapsulation Keys:           Signature Keys:               │   │
│  │  ┌─────────────────────┐      ┌─────────────────────┐       │   │
│  │  │ ML-KEM-768          │      │ ML-DSA-65           │       │   │
│  │  │ • Public: 1,184 B   │      │ • Public: 1,952 B   │       │   │
│  │  │ • Private: 2,400 B  │      │ • Private: 4,032 B  │       │   │
│  │  │   (encrypted by MK) │      │   (encrypted by MK) │       │   │
│  │  └─────────────────────┘      └─────────────────────┘       │   │
│  │                                                               │   │
│  │  ┌─────────────────────┐      ┌─────────────────────┐       │   │
│  │  │ KAZ-KEM-256         │      │ KAZ-SIGN-256        │       │   │
│  │  │ • Public: 236 B     │      │ • Public: 118 B     │       │   │
│  │  │ • Private: 86 B     │      │ • Private: 64 B     │       │   │
│  │  │   (encrypted by MK) │      │   (encrypted by MK) │       │   │
│  │  └─────────────────────┘      └─────────────────────┘       │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                    │
│                                 │ KEM Encapsulate/Decapsulate        │
│                                 ▼                                    │
│  LEVEL 3: Key Encryption Keys (KEK)                                 │
│  ══════════════════════════════════                                 │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Folder KEKs (256 bits each)                                 │   │
│  │  ───────────────────────────                                 │   │
│  │                                                               │   │
│  │  Root KEK ←──────────────── Wrapped by user's PQC public key │   │
│  │      │                                                        │   │
│  │      ├── Projects KEK ←──── Wrapped by Root KEK              │   │
│  │      │       │                                                │   │
│  │      │       ├── Project-A KEK ← Wrapped by Projects KEK     │   │
│  │      │       │                                                │   │
│  │      │       └── Project-B KEK ← Wrapped by Projects KEK     │   │
│  │      │                                                        │   │
│  │      └── Personal KEK ←──── Wrapped by Root KEK              │   │
│  │                                                               │   │
│  │  Each folder has exactly one KEK                             │   │
│  │  Child KEK wrapped by parent KEK (hierarchical)              │   │
│  │  Owner always has direct access via PQC encapsulation        │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                    │
│                                 │ AES-256-KWP wrap                   │
│                                 ▼                                    │
│  LEVEL 4: Data Encryption Keys (DEK)                                │
│  ═══════════════════════════════════                                │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  File DEKs (256 bits each)                                   │   │
│  │  ─────────────────────────                                   │   │
│  │                                                               │   │
│  │  • One unique DEK per file                                   │   │
│  │  • Generated randomly at upload time                         │   │
│  │  • Wrapped by parent folder's KEK                            │   │
│  │  • Used with AES-256-GCM for file content                    │   │
│  │  • Also encrypts file metadata                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 3. Key Types Detail

### 3.1 Authentication Secret

**Source by IdP Type**:

| IdP Type | Key Material Source | Vault Password Required |
|----------|---------------------|-------------------------|
| Passkey (WebAuthn) | PRF extension output (32 bytes) | No |
| Digital ID | SHA-256(certificate_public_key) | Yes |
| OIDC | SHA-256({sub, iss, aud}) | Yes |

**Derivation Process**:

For **Passkey (WebAuthn with PRF)**:
```
auth_secret = HKDF-SHA-384(
    ikm = prf_output,
    salt = "SecureSharing-MasterKey-v1",
    info = "mk-encryption-key",
    length = 32
)
```

For **Digital ID / OIDC** (vault password required):
```
// Step 1: Derive key from vault password using client's KDF profile
// Profile is determined by client capabilities and stored in key_derivation_salt[0]
// See algorithm-suite.md §6.2 for all supported profiles

// Example using default profile (argon2id-standard):
password_key = Argon2id(
    password = vault_password,
    salt = SHA-256(issuer + user_id)[0:16],
    memory = 65536,    // Profile-dependent: 65536 (standard), 19456 (low)
    iterations = 3,    // Profile-dependent: 3 (standard), 4 (low)
    parallelism = 4,
    length = 32
)

// Alternative: bcrypt-hkdf profile for constrained devices
// bcrypt_hash = Bcrypt(vault_password, salt, cost=13)
// password_key = HKDF-SHA-384(bcrypt_hash, "SecureSharing-Bcrypt-KDF-v1", "bcrypt-derived-key", 32)

// Step 2: Get IdP binding material
idp_material = SHA-256(binding_data)
// For Digital ID: binding_data = certificate_public_key
// For OIDC: binding_data = JSON.stringify({sub, iss, aud})

// Step 3: Combine via HKDF (NOT XOR)
auth_secret = HKDF-SHA-384(
    ikm = concatenate(password_key, idp_material),
    salt = "SecureSharing-MasterKey-v1",
    info = "mk-encryption-key",
    length = 32
)
```

**Why HKDF(concatenate(...)) instead of XOR**:
- XOR is fragile: if inputs have predictable patterns, security is weakened
- HKDF provides cryptographically secure mixing with domain separation
- HKDF is the industry standard for combining key materials

**Properties**:
- 32 bytes (256 bits)
- Bound to authentication credential
- Never stored; derived on each login
- Used only to derive MK encryption key

### 3.2 Master Key (MK)

**Generation**:
```
MK ← CSPRNG(32 bytes)
```

**Storage**:
```
// auth_secret is derived as described in Section 3.1
// It is already the encryption key (no additional HKDF needed)
mk_nonce ← CSPRNG(12 bytes)
encrypted_mk ← AES-256-GCM.Encrypt(
    key = auth_secret,
    nonce = mk_nonce,
    plaintext = MK,
    aad = user_id
)
// Store: encrypted_mk || mk_nonce
```

**Recovery**:
```
// Shamir Secret Sharing (k=3, n=5)
shares ← Shamir.Split(MK, threshold=3, total=5)
// Each share encrypted for trustee's public key
```

### 3.3 User PQC Key Pairs

**Generation** (during registration):
```
// ML-KEM key pair
(ml_kem_pk, ml_kem_sk) ← ML-KEM-768.KeyGen()

// ML-DSA key pair
(ml_dsa_pk, ml_dsa_sk) ← ML-DSA-65.KeyGen()

// KAZ-KEM key pair
(kaz_kem_pk, kaz_kem_sk) ← KAZ-KEM.KeyGen()

// KAZ-SIGN key pair
(kaz_sign_pk, kaz_sign_sk) ← KAZ-SIGN.KeyGen()
```

**Storage**:
```
// Private keys encrypted with MK
for each private_key in [ml_kem_sk, ml_dsa_sk, kaz_kem_sk, kaz_sign_sk]:
    nonce ← CSPRNG(12 bytes)
    encrypted_sk ← AES-256-GCM.Encrypt(
        key = MK,
        nonce = nonce,
        plaintext = private_key,
        aad = "private-key-" + algorithm_name
    )
    // Store: encrypted_sk || nonce

// Public keys stored in plaintext (not sensitive)
```

### 3.4 Key Encryption Key (KEK)

**Generation** (per folder):
```
KEK ← CSPRNG(32 bytes)
```

**Wrapping for Owner**:
```
// Using combined KEM
(ct_ml, ct_kaz, shared_secret) ← CombinedEncapsulate(
    owner_ml_kem_pk,
    owner_kaz_kem_pk
)
wrapped_kek ← AES-256-KWP.Wrap(shared_secret, KEK)
// Store: wrapped_kek, ct_ml, ct_kaz
```

**Wrapping for Child Folder**:
```
// Child KEK wrapped by parent KEK
wrapped_child_kek ← AES-256-KWP.Wrap(parent_KEK, child_KEK)
```

### 3.5 Data Encryption Key (DEK)

**Generation** (per file):
```
DEK ← CSPRNG(32 bytes)
```

**Wrapping**:
```
wrapped_dek ← AES-256-KWP.Wrap(folder_KEK, DEK)
```

## 4. Key Derivation Chains

### 4.1 Owner Accessing Own File

```
1. Auth Secret (from IdP authentication)
      │
      ▼ HKDF
2. MK Encryption Key
      │
      ▼ AES-256-GCM Decrypt
3. Master Key (MK)
      │
      ▼ AES-256-GCM Decrypt
4. User Private Keys (ML-KEM-SK, KAZ-KEM-SK)
      │
      ▼ Combined KEM Decapsulate
5. Root KEK
      │
      ▼ AES-256-KWP Unwrap (for each level)
6. Folder KEK (traverse hierarchy)
      │
      ▼ AES-256-KWP Unwrap
7. File DEK
      │
      ▼ AES-256-GCM Decrypt
8. Plaintext File Content
```

### 4.2 Recipient Accessing Shared File

```
1. Auth Secret (from IdP authentication)
      │
      ▼ HKDF
2. MK Encryption Key
      │
      ▼ AES-256-GCM Decrypt
3. Master Key (MK)
      │
      ▼ AES-256-GCM Decrypt
4. User Private Keys (ML-KEM-SK, KAZ-KEM-SK)
      │
      ▼ Combined KEM Decapsulate (using share grant ciphertexts)
5. Shared DEK (from ShareGrant.wrapped_key)
      │
      ▼ AES-256-GCM Decrypt
6. Plaintext File Content
```

### 4.3 Recipient Accessing Shared Folder

```
1. Auth Secret → ... → User Private Keys (same as above)
      │
      ▼ Combined KEM Decapsulate (using folder share grant ciphertexts)
2. Shared Folder KEK
      │
      ├──▶ Unwrap any file DEK in folder
      │
      └──▶ Unwrap child folder KEKs
               │
               └──▶ Access all descendant files
```

## 5. Key Lifecycle

### 5.1 Key Creation

| Key Type | When Created | Created By |
|----------|--------------|------------|
| MK | User registration | Client |
| User PQC Keys | User registration | Client |
| Root KEK | User registration | Client |
| Folder KEK | Folder creation | Client |
| DEK | File upload | Client |

### 5.2 Key Rotation

**Master Key Rotation**:
1. Generate new MK
2. Re-encrypt all user private keys with new MK
3. Generate new Shamir shares
4. Distribute to trustees
5. Update encrypted MK blob on server

**KEK Rotation** (folder):
1. Generate new KEK
2. Re-wrap all file DEKs in folder with new KEK
3. Re-wrap all child folder KEKs with new KEK
4. Update all share grants with new KEK encapsulation

**DEK Rotation** (file):
1. Decrypt file with old DEK
2. Generate new DEK
3. Re-encrypt file with new DEK
4. Update wrapped DEK

### 5.3 Key Revocation

**On User Deactivation**:
- All share grants to user are deleted
- User can no longer decapsulate any shared keys
- Own files remain encrypted (recoverable if MK recovered)

**On Share Revocation**:
- Delete ShareGrant record
- Recipient can no longer access wrapped key
- No re-encryption needed (cryptographic access removed)

## 6. Key Storage Locations

| Key | Location | State |
|-----|----------|-------|
| Auth Secret | Client memory only | Transient |
| MK Encryption Key | Client memory only | Transient |
| Master Key (MK) | Server (encrypted) | At rest |
| MK Shamir Shares | Trustees (encrypted) | At rest |
| User Public Keys | Server (plaintext) | At rest |
| User Private Keys | Server (encrypted by MK) | At rest |
| Root KEK | Server (encapsulated) | At rest |
| Folder KEKs | Server (wrapped/encapsulated) | At rest |
| File DEKs | Server (wrapped) | At rest |
| All decrypted keys | Client memory only | In use |

## 7. Security Properties

### 7.1 Key Separation
- Each file has unique DEK → compromising one file doesn't compromise others
- Each folder has unique KEK → folder-level access control
- User PQC keys separate from symmetric keys

### 7.2 Forward Secrecy
- File DEKs are random, not derived from user keys
- Compromising user keys doesn't reveal past DEKs
- Each share grant uses fresh KEM encapsulation

### 7.3 Access Control Granularity
- File-level: Share individual DEK
- Folder-level: Share folder KEK (grants access to all children)
- Hierarchical: Parent folder access implies child access

### 7.4 Server Zero-Knowledge
- Server stores only encrypted/encapsulated keys
- No plaintext keys ever transmitted to server
- Server cannot derive any key without user private keys

## 8. Implementation Requirements

### 8.1 Memory Security
```rust
// Example: Secure key storage in Rust
use zeroize::Zeroize;

struct MasterKey([u8; 32]);

impl Drop for MasterKey {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}
```

### 8.2 Key Derivation Constants

```typescript
const KEY_DERIVATION = {
  // HKDF salts (ASCII encoded)
  MASTER_KEY_SALT: "SecureSharing-MasterKey-v1",
  KEM_COMBINE_SALT: "SecureSharing-KEM-Combine-v1",
  KEK_SALT: "SecureSharing-KEK-v1",
  DEK_SALT: "SecureSharing-DEK-v1",

  // HKDF info strings
  MK_ENCRYPTION_KEY_INFO: "mk-encryption-key",
  COMBINED_SS_INFO: "combined-shared-secret",

  // KDF profiles (see algorithm-suite.md §6.2 for full specification)
  KDF_PROFILES: {
    "argon2id-standard": {  // Default — desktop, modern mobile
      algorithm: "argon2id",
      memory: 65536,        // 64 MiB
      iterations: 3,
      parallelism: 4,
      outputLength: 32,
      profileByte: 0x01,
    },
    "argon2id-low": {       // Low-RAM devices (OWASP minimum)
      algorithm: "argon2id",
      memory: 19456,        // 19 MiB
      iterations: 4,
      parallelism: 4,
      outputLength: 32,
      profileByte: 0x02,
    },
    "bcrypt-hkdf": {        // Extremely constrained devices
      algorithm: "bcrypt",
      cost: 13,
      hkdfSalt: "SecureSharing-Bcrypt-KDF-v1",
      hkdfInfo: "bcrypt-derived-key",
      outputLength: 32,
      profileByte: 0x03,
    },
  },

  // Legacy constants (for backward compatibility with profile 0x01)
  ARGON2_MEMORY: 65536,     // 64 MiB
  ARGON2_ITERATIONS: 3,
  ARGON2_PARALLELISM: 4,
  ARGON2_OUTPUT_LENGTH: 32,
};
```

## 9. Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| `DECRYPTION_FAILED` | Wrong key or corrupted data | Fail operation, log event |
| `UNWRAP_FAILED` | Invalid wrapped key | Fail operation, log event |
| `KEM_DECAPSULATION_FAILED` | Invalid ciphertext | Fail operation, log event |
| `KEY_NOT_FOUND` | Missing key in hierarchy | Fail operation, prompt re-auth |
