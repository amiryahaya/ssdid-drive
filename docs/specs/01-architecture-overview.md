# Architecture Overview

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-03

## 1. Executive Summary

SSDID Drive is an enterprise-grade, zero-trust, zero-knowledge file sharing platform with post-quantum cryptographic protection and SSDID (Self-Sovereign Digital Identity) wallet-based authentication. The system ensures that all sensitive operations occur client-side, with the server only storing encrypted data.

### Key Properties

| Property | Description |
|----------|-------------|
| **Zero-Trust** | Server is never trusted with plaintext or cryptographic keys |
| **Zero-Knowledge** | Server cannot decrypt, infer, or access file contents |
| **Post-Quantum** | Protected against quantum computing attacks |
| **Defense in Depth** | Dual-algorithm cryptography (NIST + Malaysian standards) |
| **Enterprise Recovery** | Shamir Secret Sharing for key recovery |

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SYSTEM ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                          CLIENT LAYER                               │    │
│  │                                                                      │    │
│  │  ┌──────────────────────────┐  ┌──────────────────────────────┐      │    │
│  │  │       Desktop App        │  │         Mobile App           │      │    │
│  │  │         (Tauri)          │  │       (iOS/Android)          │      │    │
│  │  │                          │  │                              │      │    │
│  │  │  • macOS                 │  │  • iOS (Swift + Rust FFI)    │      │    │
│  │  │  • Windows               │  │  • Android (Kotlin + JNI)    │      │    │
│  │  │  • Linux                 │  │                              │      │    │
│  │  │                          │  │  Hardware Security:          │      │    │
│  │  │  Hardware Security:      │  │  • Secure Enclave (iOS)      │      │    │
│  │  │  • TPM 2.0               │  │  • StrongBox (Android)       │      │    │
│  │  └────────────┬─────────────┘  └──────────────┬───────────────┘      │    │
│  │               │                               │                      │    │
│  │               └───────────────┬───────────────┘                      │    │
│  │                               │                                      │    │
│  │                               ▼                                      │    │
│  │  ┌───────────────────────────────────────────────────────────────┐  │    │
│  │  │              CRYPTO CORE (Native Rust)                        │  │    │
│  │  │                                                               │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │  │    │
│  │  │  │  Post-Quantum Cryptography                              │ │  │    │
│  │  │  │  • ML-KEM-768 (NIST)       • KAZ-KEM (Malaysian)       │ │  │    │
│  │  │  │  • ML-DSA-65 (NIST)        • KAZ-SIGN (Malaysian)      │ │  │    │
│  │  │  └─────────────────────────────────────────────────────────┘ │  │    │
│  │  │                                                               │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │  │    │
│  │  │  │  Symmetric Cryptography                                 │ │  │    │
│  │  │  │  • AES-256-GCM (File encryption)                       │ │  │    │
│  │  │  │  • AES-256-KWP (Key wrapping)                          │ │  │    │
│  │  │  │  • HKDF-SHA-384 (Key derivation)                       │ │  │    │
│  │  │  │  • HKDF-SHA3-256 (Wallet key derivation)               │ │  │    │
│  │  │  └─────────────────────────────────────────────────────────┘ │  │    │
│  │  │                                                               │  │    │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │  │    │
│  │  │  │  Key Management                                         │ │  │    │
│  │  │  │  • Master Key derivation                               │ │  │    │
│  │  │  │  • KEK/DEK hierarchy                                   │ │  │    │
│  │  │  │  • Shamir Secret Sharing                               │ │  │    │
│  │  │  └─────────────────────────────────────────────────────────┘ │  │    │
│  │  │                                                               │  │    │
│  │  └───────────────────────────────────────────────────────────────┘  │    │
│  │                                                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    │ HTTPS (TLS 1.3)                        │
│                                    │ (Server cannot decrypt payload)        │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         SERVER LAYER                                 │    │
│  │                                                                      │    │
│  │  ┌───────────────────────────────────────────────────────────────┐  │    │
│  │  │                      API Gateway                               │  │    │
│  │  │  • Authentication (verify tokens)                             │  │    │
│  │  │  • Rate limiting                                              │  │    │
│  │  │  • Request validation                                         │  │    │
│  │  │  • TLS termination                                            │  │    │
│  │  └───────────────────────────────────────────────────────────────┘  │    │
│  │                              │                                       │    │
│  │         ┌────────────────────┼────────────────────┐                 │    │
│  │         ▼                    ▼                    ▼                 │    │
│  │  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐        │    │
│  │  │    Auth     │      │    Files    │      │   Sharing   │        │    │
│  │  │   Service   │      │   Service   │      │   Service   │        │    │
│  │  │             │      │             │      │             │        │    │
│  │  │  • SSDID   │      │  • Upload   │      │  • Grants   │        │    │
│  │  │    Wallet  │      │  • Download │      │  • Verify   │        │    │
│  │  │  • DID     │      │  • Metadata │      │  • Revoke   │        │    │
│  │  │    Auth    │      │             │      │             │        │    │
│  │  └─────────────┘      └─────────────┘      └─────────────┘        │    │
│  │         │                    │                    │                 │    │
│  │         └────────────────────┼────────────────────┘                 │    │
│  │                              ▼                                       │    │
│  │  ┌───────────────────────────────────────────────────────────────┐  │    │
│  │  │                       DATA LAYER                               │  │    │
│  │  │                                                                │  │    │
│  │  │  ┌─────────────────────┐    ┌───────────────────────────────┐ │  │    │
│  │  │  │     PostgreSQL      │    │      Object Storage          │ │  │    │
│  │  │  │                     │    │        (S3/MinIO)            │ │  │    │
│  │  │  │  • Users            │    │                              │ │  │    │
│  │  │  │  • Tenants          │    │  • Encrypted blobs           │ │  │    │
│  │  │  │  • Folders          │    │  • Chunked uploads           │ │  │    │
│  │  │  │  • Files (metadata) │    │  • Pre-signed URLs           │ │  │    │
│  │  │  │  • Shares           │    │                              │ │  │    │
│  │  │  │  • Key bundles      │    │                              │ │  │    │
│  │  │  │    (encrypted)      │    │                              │ │  │    │
│  │  │  └─────────────────────┘    └───────────────────────────────┘ │  │    │
│  │  │                                                                │  │    │
│  │  └───────────────────────────────────────────────────────────────┘  │    │
│  │                                                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3. Component Details

### 3.1 Client Layer

SSDID Drive uses **native clients exclusively** for maximum security. The crypto core is implemented in Rust and deployed as native libraries with platform-specific bindings.

#### Platform Security Features

| Concern | Desktop (Native) | Mobile (Native) |
|---------|------------------|-----------------|
| Key Storage | OS Keychain, TPM | Keychain, Secure Enclave |
| Hardware Security | TPM 2.0 access | Secure Enclave/StrongBox |
| Memory Protection | `mlock()`, secure heap | Process isolation |
| PQC Support | Native Rust | Native Rust via FFI |
| Attack Surface | Process isolation | Sandboxed |

#### Supported Platforms

| Platform | Security Level | Technology |
|----------|---------------|------------|
| **Desktop (Tauri)** | Highest | Rust backend, native UI |
| **iOS** | High | Swift + Rust FFI |
| **Android** | High | Kotlin + Rust FFI |

> **Why Native?** Browser-based clients cannot access hardware security modules (TPM, Secure Enclave, StrongBox), have limited memory protection, and are vulnerable to extension attacks and XSS. For zero-trust architecture, native clients are required.

#### Desktop Application
- **Technology**: Tauri (Rust backend, native UI)
- **Platforms**: macOS, Windows, Linux
- **Crypto**: Native Rust implementation
- **Key Storage**:
  - macOS: Keychain + Secure Enclave
  - Windows: DPAPI + TPM 2.0
  - Linux: Secret Service API + TPM 2.0
- **File Processing**: Native file system access with streaming

#### Mobile Application
- **Technology**: Native (Swift for iOS, Kotlin for Android) with Rust FFI
- **Platforms**: iOS 15+, Android 10+
- **Crypto**: Rust library via FFI bindings
- **Key Storage**:
  - iOS: Keychain + Secure Enclave (A7+ chips)
  - Android: Keystore + StrongBox (if available)
- **File Processing**: Chunked processing for memory efficiency

### 3.2 Crypto Core (Rust Library)

The crypto core is implemented as a native Rust library with platform-specific bindings:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CRYPTO CORE ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    securesharing-crypto (Rust crate)                  │  │
│  │                                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │  │
│  │  │   ml-kem    │  │   ml-dsa    │  │   kaz-kem   │  │  kaz-sign   │ │  │
│  │  │   (NIST)    │  │   (NIST)    │  │ (Malaysian) │  │ (Malaysian) │ │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │  │
│  │                                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │  │
│  │  │  aes-gcm    │  │    hkdf     │  │  argon2id   │  │   shamir    │ │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │  │                    Secure Memory Module                         │ │  │
│  │  │  • mlock() to prevent swapping                                 │ │  │
│  │  │  • Zeroize on drop                                             │ │  │
│  │  │  • Guard pages for buffer overflow detection                   │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│          ┌────────────────────┬────────────────────┬────────────────────┐  │
│          ▼                    ▼                    ▼                    │  │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐   │  │
│  │   Tauri Plugin    │  │    Swift FFI      │  │    Kotlin JNI     │   │  │
│  │     (Desktop)     │  │      (iOS)        │  │    (Android)      │   │  │
│  └───────────────────┘  └───────────────────┘  └───────────────────┘   │  │
│                                                                          │  │
└─────────────────────────────────────────────────────────────────────────────┘
```

```rust
// High-level crypto interface
pub trait CryptoProvider {
    // Key Encapsulation
    fn kem_keygen(&self) -> Result<(PublicKey, PrivateKey)>;
    fn kem_encapsulate(&self, pk: &PublicKey) -> Result<(Ciphertext, SharedSecret)>;
    fn kem_decapsulate(&self, sk: &PrivateKey, ct: &Ciphertext) -> Result<SharedSecret>;

    // Digital Signatures
    fn sign_keygen(&self) -> Result<(PublicKey, PrivateKey)>;
    fn sign(&self, sk: &PrivateKey, msg: &[u8]) -> Result<Signature>;
    fn verify(&self, pk: &PublicKey, msg: &[u8], sig: &Signature) -> Result<bool>;
}

// Platform-specific secure key storage
pub trait SecureKeyStorage {
    fn store(&self, key_id: &str, key: &[u8]) -> Result<()>;
    fn retrieve(&self, key_id: &str) -> Result<SecureBytes>;
    fn delete(&self, key_id: &str) -> Result<()>;
}

// Implementations
struct NistProvider;      // ML-KEM-768, ML-DSA-65
struct KazProvider;       // KAZ-KEM, KAZ-SIGN
struct HybridProvider;    // Combined NIST + KAZ

// Platform key storage implementations
struct MacOSKeychain;     // macOS Keychain + Secure Enclave
struct WindowsDpapi;      // Windows DPAPI + TPM
struct LinuxSecretService;// Linux Secret Service + TPM
struct IOSKeychain;       // iOS Keychain + Secure Enclave
struct AndroidKeystore;   // Android Keystore + StrongBox
```

### 3.3 Server Layer

#### API Gateway
- Request routing and load balancing
- TLS 1.3 termination
- Rate limiting (per-IP and per-user)
- Request/response logging (no sensitive data)

#### Auth Service
- SSDID wallet DID-based challenge-response authentication
- Verifiable Credential issuance and verification
- Session token management (Redis-backed)
- DID public key storage (zero-knowledge)

#### Files Service
- Pre-signed URL generation
- Upload/download coordination
- Quota management
- Integrity verification

#### Sharing Service
- Share grant creation/validation
- Signature verification
- Permission enforcement
- Revocation handling

### 3.4 Data Layer

#### PostgreSQL
Stores structured data with row-level security:

| Table | Contents | Encrypted? |
|-------|----------|------------|
| tenants | Organization configuration | No |
| users | User profiles | Partial |
| key_bundles | Encrypted keys | Yes (client-side) |
| credentials | Public keys, counter | No (public data) |
| folders | Folder metadata | Yes (client-side) |
| files | File metadata | Yes (client-side) |
| shares | Share grants | Partial |

#### Object Storage
Stores encrypted file content:
- All blobs are encrypted before upload
- Server only stores ciphertext
- Pre-signed URLs for direct upload/download

## 4. Key Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          KEY HIERARCHY                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Level 0: Authentication                                                    │
│  ───────────────────────                                                    │
│                                                                              │
│  ┌────────────────────┐                                                     │
│  │  Auth Secret       │  ← SSDID Wallet (DID key material)                  │
│  │  (from Wallet)     │                                                     │
│  └─────────┬──────────┘                                                     │
│            │ HKDF                                                           │
│            ▼                                                                │
│  Level 1: Master Key                                                        │
│  ───────────────────                                                        │
│                                                                              │
│  ┌────────────────────┐                                                     │
│  │    Master Key      │  ← 256-bit, encrypted at rest                       │
│  │       (MK)         │  ← Shamir-split for recovery                        │
│  └─────────┬──────────┘                                                     │
│            │ AES-256-GCM decrypt                                            │
│            ▼                                                                │
│  Level 2: User Key Pairs                                                    │
│  ───────────────────────                                                    │
│                                                                              │
│  ┌────────────────────┐  ┌────────────────────┐                             │
│  │   ML-KEM-768       │  │    ML-DSA-65       │                             │
│  │   Key Pair         │  │    Key Pair        │                             │
│  └────────────────────┘  └────────────────────┘                             │
│  ┌────────────────────┐  ┌────────────────────┐                             │
│  │    KAZ-KEM         │  │    KAZ-SIGN        │                             │
│  │    Key Pair        │  │    Key Pair        │                             │
│  └─────────┬──────────┘  └────────────────────┘                             │
│            │                                                                │
│            │ KEM Decapsulation                                              │
│            ▼                                                                │
│  Level 3: Key Encryption Keys (KEK)                                         │
│  ──────────────────────────────────                                         │
│                                                                              │
│  ┌────────────────────┐  ┌────────────────────┐                             │
│  │    Root KEK        │  │   Folder KEKs      │                             │
│  │  (vault root)      │──│  (per folder)      │                             │
│  └─────────┬──────────┘  └─────────┬──────────┘                             │
│            │                       │                                        │
│            │ AES-256-KWP unwrap    │                                        │
│            ▼                       ▼                                        │
│  Level 4: Data Encryption Keys (DEK)                                        │
│  ───────────────────────────────────                                        │
│                                                                              │
│  ┌────────────────────┐  ┌────────────────────┐                             │
│  │     File DEK       │  │     File DEK       │  ...                        │
│  │   (per file)       │  │   (per file)       │                             │
│  └────────────────────┘  └────────────────────┘                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5. Multi-Tenant Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MULTI-TENANT ISOLATION                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                           TENANT A                                   │    │
│  │                                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │   User A1   │  │   User A2   │  │   User A3   │                  │    │
│  │  │   (keys)    │  │   (keys)    │  │   (keys)    │                  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │    │
│  │         │              │              │                              │    │
│  │         └──────────────┼──────────────┘                              │    │
│  │                        ▼                                             │    │
│  │            ┌─────────────────────────┐                               │    │
│  │            │  Tenant A Encrypted     │                               │    │
│  │            │  Data (isolated)        │                               │    │
│  │            └─────────────────────────┘                               │    │
│  │                                                                      │    │
│  │  Configuration:                                                      │    │
│  │  • Auth: SSDID Wallet                                               │    │
│  │  • Recovery: 3-of-5 trustees                                        │    │
│  │  • Storage: 1TB quota                                               │    │
│  │                                                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                           TENANT B                                   │    │
│  │                                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐                                   │    │
│  │  │   User B1   │  │   User B2   │                                   │    │
│  │  │   (keys)    │  │   (keys)    │                                   │    │
│  │  └─────────────┘  └─────────────┘                                   │    │
│  │         │              │                                             │    │
│  │         └──────────────┘                                             │    │
│  │                ▼                                                     │    │
│  │      ┌─────────────────────────┐                                    │    │
│  │      │  Tenant B Encrypted     │                                    │    │
│  │      │  Data (isolated)        │                                    │    │
│  │      └─────────────────────────┘                                    │    │
│  │                                                                      │    │
│  │  Configuration:                                                      │    │
│  │  • Auth: SSDID Wallet                                               │    │
│  │  • Recovery: 2-of-3 trustees                                        │    │
│  │  • Storage: 500GB quota                                             │    │
│  │                                                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ISOLATION GUARANTEES:                                                      │
│  • Users in Tenant A cannot access Tenant B data                           │
│  • Different cryptographic keys per tenant                                  │
│  • Separate storage namespaces                                              │
│  • Independent auth configurations                                           │
│  • Cross-tenant sharing is BLOCKED by design                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 6. Data Flow Patterns

### 6.1 Upload Flow

```
User → Select File → Encrypt (DEK) → Wrap DEK (KEK) → Sign → Upload → Server (stores ciphertext)
```

### 6.2 Download Flow

```
User → Request → Server (returns ciphertext) → Verify → Unwrap DEK → Decrypt → Plaintext
```

### 6.3 Share Flow

```
Owner → Get Recipient PK → Encapsulate DEK → Sign → Create Grant → Recipient can decrypt
```

## 7. Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Desktop Client** | Tauri + Rust | Desktop app (macOS, Windows, Linux) |
| **iOS Client** | Swift + Rust FFI | iOS native app |
| **Android Client** | Kotlin + Rust JNI | Android native app |
| **Crypto Core** | Rust (native) | Cryptographic operations |
| **Backend** | ASP.NET Core 10 (.NET 10) | API services (Minimal APIs) |
| **Database** | PostgreSQL | Relational data |
| **Object Storage** | MinIO/S3 | Encrypted blobs |
| **Cache** | Redis | Sessions, challenges |
| **Message Queue** | NATS/RabbitMQ | Async events |

### 7.1 Client Platform Requirements

| Platform | Minimum Version | Secure Hardware | Security Level | Status |
|----------|-----------------|-----------------|----------------|--------|
| macOS | 11.0 (Big Sur) | Secure Enclave (T1/T2/M1+) | High | ✅ Production |
| Windows | 10 (1903+) | TPM 2.0 | High | ✅ Production |
| Linux | Ubuntu 20.04+ | TPM 2.0 (optional) | High | ✅ Production |
| iOS | 15.0+ | Secure Enclave (A7+) | High | ✅ Production |
| Android | 10 (API 29)+ | StrongBox (optional) | High | ✅ Production |

## 8. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        LOAD BALANCER                                 │    │
│  │                    (TLS termination)                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                │                                            │
│                    ┌───────────┼───────────┐                               │
│                    ▼           ▼           ▼                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                         │
│  │ API Pod 1   │  │ API Pod 2   │  │ API Pod 3   │    (Kubernetes)         │
│  └─────────────┘  └─────────────┘  └─────────────┘                         │
│                                │                                            │
│                    ┌───────────┴───────────┐                               │
│                    ▼                       ▼                               │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                  │
│  │       PostgreSQL        │  │      Object Storage     │                  │
│  │      (Primary +         │  │        (MinIO)          │                  │
│  │        Replica)         │  │                         │                  │
│  └─────────────────────────┘  └─────────────────────────┘                  │
│                                                                              │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                  │
│  │         Redis           │  │      Message Queue      │                  │
│  │   (Sessions, Cache)     │  │     (Event Bus)         │                  │
│  └─────────────────────────┘  └─────────────────────────┘                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 9. Security Architecture

See [02-threat-model.md](./02-threat-model.md) for detailed threat analysis.

### Key Security Features

1. **End-to-end Encryption**: All sensitive data encrypted client-side
2. **Zero-Knowledge Server**: Server cannot decrypt any content
3. **Post-Quantum Protection**: ML-KEM + KAZ-KEM dual algorithm
4. **Digital Signatures**: ML-DSA + KAZ-SIGN for integrity
5. **Key Recovery**: Shamir Secret Sharing (k-of-n threshold)
6. **Multi-tenant Isolation**: Cryptographic separation between tenants
