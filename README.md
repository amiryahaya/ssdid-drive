# SecureSharing

**Enterprise Zero-Trust, Zero-Knowledge File Sharing with Post-Quantum Cryptography**

## Overview

SecureSharing is an enterprise-grade secure file sharing platform built on three core principles:

1. **Zero-Trust**: The server is never trusted with plaintext data or encryption keys
2. **Zero-Knowledge**: The server cannot decrypt, infer, or access file contents
3. **Post-Quantum Security**: Dual PQC algorithm support (NIST + Malaysian KAZ) for quantum resistance

## Key Features

- **End-to-end encryption** with client-side key generation
- **Post-quantum cryptography** using ML-KEM-768, ML-DSA-65, KAZ-KEM, and KAZ-SIGN
- **Invitation-only onboarding** with controlled access
- **Shamir secret sharing** for key recovery without central escrow
- **Multi-tenant architecture** with isolated data per organization
- **Native mobile apps** (iOS/Android) with hardware-backed key storage

## Security Guarantees

| Property | Guarantee |
|----------|-----------|
| Confidentiality | Server cannot read file contents or metadata |
| Integrity | Tampered files detected via signatures |
| Authenticity | Share grants cryptographically signed by grantor |
| Forward Secrecy | Unique DEK per file, unique KEK per folder |
| Quantum Resistance | Dual PQC algorithms (both must be broken) |
| Key Recovery | Shamir (k,n) threshold without central escrow |

## Technology Stack

| Component | Technology |
|-----------|------------|
| Backend | Elixir/Phoenix (OTP) |
| Database | PostgreSQL 18 (UUIDv7) |
| Object Storage | S3-compatible (Garage) |
| iOS Client | Swift + Rust FFI |
| Android Client | Kotlin + Rust JNI |
| Desktop Client | Tauri + Rust |
| PQC (NIST) | ML-KEM-768, ML-DSA-65 |
| PQC (Malaysian) | KAZ-KEM, KAZ-SIGN |
| Symmetric | AES-256-GCM, HKDF-SHA384, Argon2id |
| Authentication | WebAuthn, OIDC, Digital ID |

## Getting Started

### Prerequisites

- Elixir 1.15+
- PostgreSQL 16+
- Node.js 20+ (for asset compilation)

### Backend Setup

```bash
# Install dependencies
mix setup

# Start the Phoenix server
mix phx.server

# Or run inside IEx
iex -S mix phx.server
```

The server will be available at [`localhost:4000`](http://localhost:4000).

### Mobile Development

#### Android

```bash
cd android
./gradlew assembleDevDebug
```

#### iOS

```bash
cd ios/SecureSharing
open SecureSharing.xcodeproj
```

### Running Tests

```bash
# Backend tests
mix test

# Android tests
cd android && ./gradlew testDevDebugUnitTest

# iOS tests
cd ios/SecureSharing && xcodebuild test -scheme SecureSharing -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Documentation

Full documentation is available in the [`/docs`](./docs) directory:

### Core Specifications
- [Architecture Overview](./docs/specs/01-architecture-overview.md)
- [Threat Model](./docs/specs/02-threat-model.md)

### Cryptographic Protocols
- [Algorithm Suite](./docs/crypto/01-algorithm-suite.md) - ML-KEM, ML-DSA, KAZ-KEM, KAZ-SIGN
- [Key Hierarchy](./docs/crypto/02-key-hierarchy.md) - Master Key → KEK → DEK derivation
- [Encryption Protocol](./docs/crypto/03-encryption-protocol.md) - File encryption format
- [Shamir Recovery](./docs/crypto/06-shamir-recovery.md) - Secret sharing for recovery

### API Specification
- [Authentication](./docs/api/01-authentication.md)
- [Files](./docs/api/03-files.md)
- [Sharing](./docs/api/05-sharing.md)
- [Invitations](./docs/api/09-invitations.md)

### Operation Flows
- [Registration Flow](./docs/flows/01-registration-flow.md)
- [Upload Flow](./docs/flows/03-upload-flow.md)
- [Share File Flow](./docs/flows/05-share-file-flow.md)
- [Invitation Flow](./docs/flows/09-invitation-flow.md)
- [Recovery Flow](./docs/flows/08-recovery-flow.md)

### Features
- [Invitation System](./docs/design/invitation-system.md)
- [Multi-Tenant Users](./docs/features/multi-tenant-users.md)

## Key Hierarchy

```
Passkey/Digital ID
        │
        ▼
   Master Key (MK) ──────────────────────────────────────┐
        │                                                │
        │ encrypts                                       │
        ▼                                                ▼
   User PQC Key Pairs                              Shamir Shares
   - ML-KEM (encapsulation)                        (for recovery)
   - ML-DSA (signatures)
   - KAZ-KEM (encapsulation)
   - KAZ-SIGN (signatures)
        │
        │ encapsulates/decapsulates
        ▼
   Key Encryption Keys (KEK)
   - One per folder
   - Hierarchical inheritance
        │
        │ wraps/unwraps
        ▼
   Data Encryption Keys (DEK)
   - One per file
   - AES-256-GCM
```

## Project Structure

```
SecureSharing/
├── lib/                    # Elixir backend
│   ├── secure_sharing/     # Business logic
│   └── secure_sharing_web/ # Phoenix web layer
├── android/                # Android app (Kotlin)
├── ios/                    # iOS app (Swift)
├── native/                 # Native crypto libraries
│   ├── kaz_kem/           # KAZ-KEM implementation
│   ├── ml_kem/            # ML-KEM bindings
│   └── ml_dsa/            # ML-DSA bindings
├── docs/                   # Full documentation
└── priv/                   # Static assets & migrations
```

## License

Proprietary - All rights reserved.
