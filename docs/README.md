# SecureSharing Documentation

**Enterprise Zero-Trust, Zero-Knowledge File Sharing with Post-Quantum Cryptography**

## Overview

SecureSharing is an enterprise-grade secure file sharing platform built on three core principles:

1. **Zero-Trust**: The server is never trusted with plaintext data or encryption keys
2. **Zero-Knowledge**: The server cannot decrypt, infer, or access file contents
3. **Post-Quantum Security**: Dual PQC algorithm support (NIST + Malaysian KAZ) for quantum resistance

## Documentation Structure

### Core Specifications

| Section | Description |
|---------|-------------|
| [Architecture Overview](./specs/01-architecture-overview.md) | System components and design |
| [Threat Model](./specs/02-threat-model.md) | Security assumptions and attack vectors |
| [Sharing Permission Model](./specs/04-sharing-permission-model.md) | **File/folder sharing logic, permissions, encryption keys, audit logging** |

### Cryptographic Protocols

| Document | Description |
|----------|-------------|
| [Algorithm Suite](./crypto/01-algorithm-suite.md) | ML-KEM, ML-DSA, KAZ-KEM, KAZ-SIGN specifications |
| [Key Hierarchy](./crypto/02-key-hierarchy.md) | Master Key → KEK → DEK derivation chains |
| [Encryption Protocol](./crypto/03-encryption-protocol.md) | File encryption format and chunking |
| [Key Encapsulation](./crypto/04-key-encapsulation.md) | KEM operations for secure sharing |
| [Signature Protocol](./crypto/05-signature-protocol.md) | Digital signatures and verification |
| [Shamir Recovery](./crypto/06-shamir-recovery.md) | Secret sharing for key recovery |
| [Test Vectors](./crypto/07-test-vectors.md) | Known-answer tests for validation |

### Data Model

| Document | Description |
|----------|-------------|
| [Entities](./data-model/01-entities.md) | User, Tenant, File, Folder, Share definitions |
| [Database Schema](./data-model/02-database-schema.md) | PostgreSQL DDL statements |
| [TypeScript Interfaces](./data-model/03-typescript-interfaces.md) | Client-side type definitions |
| [Wire Format](./data-model/04-wire-format.md) | Request/response JSON schemas |

### API Specification

| Document | Description |
|----------|-------------|
| [Authentication](./api/01-authentication.md) | Auth endpoints and token format |
| [Users](./api/02-users.md) | User registration and profile |
| [Files](./api/03-files.md) | Upload, download, metadata |
| [Folders](./api/04-folders.md) | Folder CRUD and hierarchy |
| [Sharing](./api/05-sharing.md) | Share grants and permissions |
| [Recovery](./api/06-recovery.md) | Trustee and recovery endpoints |
| [Error Codes](./api/07-error-codes.md) | Error response definitions |
| [Notifications](./api/08-notifications.md) | Push notifications, WebSocket channel, read tracking |
| [Invitations](./api/09-invitations.md) | Invitation-only user onboarding |

### Operation Flows

| Document | Description |
|----------|-------------|
| [Registration Flow](./flows/01-registration-flow.md) | User onboarding with key generation |
| [Login Flow](./flows/02-login-flow.md) | Authentication and key derivation |
| [Upload Flow](./flows/03-upload-flow.md) | Client-side encryption and upload |
| [Download Flow](./flows/04-download-flow.md) | Download and decryption |
| [Share File Flow](./flows/05-share-file-flow.md) | Single file sharing |
| [Share Folder Flow](./flows/06-share-folder-flow.md) | Folder sharing with children |
| [Revoke Access Flow](./flows/07-revoke-access-flow.md) | Permission revocation |
| [Recovery Flow](./flows/08-recovery-flow.md) | Shamir-based key reconstruction |
| [Invitation Flow](./flows/09-invitation-flow.md) | Invitation-based user onboarding |

### Identity Provider Integration

| Document | Description |
|----------|-------------|
| [Provider Interface](./idp/01-provider-interface.md) | IdP abstraction contract |
| [WebAuthn Adapter](./idp/02-webauthn-adapter.md) | Passkey implementation |
| [Digital ID Adapter](./idp/03-digital-id-adapter.md) | Malaysian Digital ID integration |
| [OIDC Adapter](./idp/04-oidc-adapter.md) | Generic OIDC/OAuth2 adapter |

### Deployment & Sizing

| Document | Description |
|----------|-------------|
| [Hardware Sizing Guide](./deployment/hardware-sizing-guide.md) | Component requirements, deployment scenarios, all provider recommendations |
| [Hetzner Two-Server Deployment](./deployment/hetzner-two-server-deployment.md) | Full deployment guide for Hetzner bare metal |
| [Contabo Hosting Sizing](./deployment/contabo-hosting-sizing.md) | Contabo VPS/VDS/bare metal options (EU and Singapore) |
| [IPServerOne Hosting Sizing](./deployment/ipserverone-hosting-sizing.md) | Malaysia-local deployment (Cyberjaya), NovaGPU for GPU LLM |
| [Monitoring & Observability](./deployment/monitoring-observability.md) | Telemetry metrics, Prometheus, Grafana dashboards, alerting, OpenTelemetry |
| [Troubleshooting](./deployment/troubleshooting.md) | Common failures, debug procedures, secret rotation, emergency procedures |
| [Backup & Restore](./deployment/backup-restore.md) | PostgreSQL backup, S3 replication, disaster recovery, RTO/RPO |

*Provider pricing last researched: February 2026.*

### Features

| Document | Description |
|----------|-------------|
| [Feature Roadmap](./features/features.md) | Complete feature roadmap for all platforms |
| [Multi-Tenant Users](./features/multi-tenant-users.md) | Users belonging to multiple tenants |
| [Device Enrollment](./features/device-enrollment.md) | Device binding and attestation |
| [Invitation System](./design/invitation-system.md) | Invitation-only onboarding design |

## Key Concepts

### Key Hierarchy

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

### Why DEK and KEK?

| Key | Purpose | Benefit |
|-----|---------|---------|
| **DEK** (Data Encryption Key) | Encrypts file content | Each file isolated; compromise one ≠ compromise all |
| **KEK** (Key Encryption Key) | Wraps DEKs per folder | Share folder = share KEK (not Master Key) |

**Key insight**: Revoking access only requires re-wrapping keys (32 bytes), not re-encrypting entire files. See [Key Hierarchy](./crypto/02-key-hierarchy.md) for details.

### Security Guarantees

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
| Desktop Client | Tauri + Rust (macOS, Windows, Linux) |
| iOS Client | Swift + Rust FFI |
| Android Client | Kotlin + Rust JNI |
| Crypto Core | Native Rust library |
| PQC (NIST) | ML-KEM-768, ML-DSA-65 |
| PQC (Malaysian) | KAZ-KEM, KAZ-SIGN |
| Symmetric | AES-256-GCM, HKDF-SHA384, Argon2id |
| Backend | Elixir/Phoenix (OTP) |
| Database | PostgreSQL 18 (UUIDv7) |
| Object Storage | S3-compatible (Garage) |
| Authentication | WebAuthn, OIDC, Digital ID |

### Client Platforms

SecureSharing uses **native clients exclusively** for maximum security:

| Platform | Technology | Key Storage | Status |
|----------|------------|-------------|--------|
| Desktop | Tauri (Rust) | Keychain, DPAPI, Secret Service + TPM | ✅ Production |
| iOS | Swift + Rust FFI | Keychain + Secure Enclave | ✅ Production |
| Android | Kotlin + Rust FFI | Keystore + StrongBox | ✅ Production |

**Why Native?**
- **Hardware Security**: Native apps access Secure Enclave, TPM 2.0, StrongBox
- **Secure Key Storage**: OS keychain integration with hardware-backed keys
- **Memory Protection**: `mlock()`, secure memory wiping, process isolation
- **PQC Performance**: Native Rust libraries provide optimal performance
- **Reduced Attack Surface**: Process isolation, no browser-based vulnerabilities

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 0.2.0 | 2026-01-18 | Added notifications API, push notifications, email notifications, local caching |
| 0.1.0 | 2025-01 | Initial specification draft |
