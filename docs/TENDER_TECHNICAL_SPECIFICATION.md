# SecureSharing - Technical Specification for Tender

**Document Version**: 1.2.0
**Date**: February 2026
**Classification**: Commercial-in-Confidence

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Overview](#2-system-overview)
3. [Security Framework](#3-security-framework)
4. [Cryptographic Specifications](#4-cryptographic-specifications)
5. [Platform Support](#5-platform-support)
6. [Core Capabilities](#6-core-capabilities)
7. [PII Protection Service](#7-pii-protection-service)
8. [Integration Capabilities](#8-integration-capabilities)
9. [Deployment & Operations](#9-deployment--operations)
10. [Compliance & Standards](#10-compliance--standards)
11. [Technical Requirements](#11-technical-requirements)

---

## 1. Executive Summary

### 1.1 Product Overview

SecureSharing is an enterprise-grade secure file sharing platform designed with zero-trust and zero-knowledge principles. The system ensures complete data confidentiality through client-side encryption, meaning server infrastructure never has access to plaintext data or encryption keys.

### 1.2 Core Principles

| Principle | Description |
|-----------|-------------|
| **Zero-Trust** | Server infrastructure is never trusted with plaintext data or cryptographic keys |
| **Zero-Knowledge** | Server cannot decrypt, infer, or access file contents |
| **Post-Quantum Security** | Protected against future quantum computing attacks using dual PQC algorithms |
| **Defense in Depth** | Dual-algorithm cryptography (NIST + Malaysian standards) |
| **Enterprise Recovery** | Shamir Secret Sharing for key recovery without central escrow |

### 1.3 Security Guarantees

| Property | Guarantee |
|----------|-----------|
| **Confidentiality** | Server cannot read file contents or metadata |
| **Integrity** | Tampered files detected via digital signatures |
| **Authenticity** | Share grants cryptographically signed by grantor |
| **Forward Secrecy** | Unique encryption key per file |
| **Quantum Resistance** | Dual PQC algorithms must both be broken to compromise security |
| **Key Recovery** | Threshold-based recovery without central escrow |

---

## 2. System Overview

### 2.1 Solution Components

| Component | Description |
|-----------|-------------|
| **Desktop Application** | Native cross-platform application for macOS, Windows, and Linux |
| **iOS Application** | Native iOS application with hardware security integration |
| **Android Application** | Native Android application with hardware security integration |
| **Backend Services** | Scalable API services for authentication, file management, and sharing |
| **PII Protection Service** | Standalone service for document redaction and AI-assisted queries |

### 2.2 Key Design Characteristics

- **Client-Side Encryption**: All encryption/decryption operations occur on user devices
- **Hierarchical Key Management**: Multi-level key structure (Master Key → Folder Keys → File Keys)
- **Multi-Tenant Architecture**: Complete tenant isolation with independent encryption keys
- **Hardware Security Integration**: Leverages platform hardware security modules (TPM, Secure Enclave, StrongBox)
- **Offline Capability**: Full functionality with automatic synchronization when online

---

## 3. Security Framework

### 3.1 Trust Model

| Zone | Trust Level | Description |
|------|-------------|-------------|
| **Client Applications** | Trusted | Signed native applications perform all cryptographic operations |
| **Identity Providers** | Semi-Trusted | Used for authentication only, never for key material |
| **Server Infrastructure** | Untrusted | Zero-knowledge design - server cannot access plaintext |

### 3.2 Threat Protection

| Threat | Protection |
|--------|------------|
| **Server Compromise** | Client-side encryption ensures data remains protected |
| **Network Interception** | TLS 1.3 with certificate pinning |
| **Insider Threat** | Per-user encryption keys, signed share grants, audit trails |
| **Quantum Computing** | Dual post-quantum cryptographic algorithms |
| **Credential Loss** | Threshold-based key recovery system |

### 3.3 Security Controls

| Category | Controls |
|----------|----------|
| **Preventive** | Client-side encryption, post-quantum key encapsulation, digital signatures, tenant isolation |
| **Detective** | Comprehensive audit logging, signature verification, integrity checking |
| **Corrective** | Key rotation, share revocation, credential revocation, recovery system |

---

## 4. Cryptographic Specifications

### 4.1 Algorithm Suite

| Purpose | Algorithm | Standard |
|---------|-----------|----------|
| Key Encapsulation (Primary) | ML-KEM-768 | NIST FIPS 203 |
| Key Encapsulation (Secondary) | KAZ-KEM-256 | Malaysian Standard |
| Digital Signatures (Primary) | ML-DSA-65 | NIST FIPS 204 |
| Digital Signatures (Secondary) | KAZ-SIGN-256 | Malaysian Standard |
| File Encryption | AES-256-GCM | NIST |
| Key Derivation | HKDF-SHA-384 | RFC 5869 |
| Password Hashing | Argon2id | RFC 9106 |
| Key Wrapping | AES-256-KWP | RFC 5649 |

### 4.2 Post-Quantum Key Encapsulation

**ML-KEM-768 (NIST)**

| Parameter | Value |
|-----------|-------|
| Security Level | NIST Level 3 (AES-192 equivalent) |
| Public Key Size | 1,184 bytes |
| Ciphertext Size | 1,088 bytes |

**KAZ-KEM-256 (Malaysian)**

| Parameter | Value |
|-----------|-------|
| Security Level | 256-bit (NIST Level 5 equivalent) |
| Public Key Size | 236 bytes |
| Ciphertext Size | 354 bytes |

### 4.3 Post-Quantum Digital Signatures

**ML-DSA-65 (NIST)**

| Parameter | Value |
|-----------|-------|
| Security Level | NIST Level 3 (AES-192 equivalent) |
| Public Key Size | 1,952 bytes |
| Signature Size | 3,309 bytes |

**KAZ-SIGN-256 (Malaysian)**

| Parameter | Value |
|-----------|-------|
| Security Level | 256-bit (NIST Level 5 equivalent) |
| Public Key Size | 118 bytes |
| Signature Size | 356 bytes |

### 4.4 Defense in Depth

The system combines both NIST and Malaysian post-quantum algorithms. An attacker must break **both** algorithm families to compromise security, providing protection against algorithm-specific vulnerabilities.

---

## 5. Platform Support

### 5.1 Desktop Application

| Specification | Details |
|---------------|---------|
| **Supported Platforms** | macOS 11.0+, Windows 10 (1903+), Linux (Ubuntu 20.04+) |
| **Architectures** | x86_64, ARM64 |
| **Hardware Security** | Secure Enclave (macOS), TPM 2.0 (Windows/Linux) |
| **Distribution** | Platform-native installers |

**Capabilities:**
- Native file system integration
- System tray with quick actions
- Biometric authentication (Touch ID, Windows Hello)
- Keyboard shortcuts
- Offline mode with sync
- Drag and drop operations

### 5.2 iOS Application

| Specification | Details |
|---------------|---------|
| **Minimum Version** | iOS 15.0+ |
| **Hardware Security** | Secure Enclave, iOS Keychain |
| **Extensions** | Share Extension, File Provider Extension |

### 5.3 Android Application

| Specification | Details |
|---------------|---------|
| **Minimum Version** | Android 7.0+ (API 24) |
| **Hardware Security** | StrongBox, Android KeyStore |
| **Features** | Share intent handling, screenshot prevention |

### 5.4 Security Capabilities by Platform

| Capability | Desktop | iOS | Android |
|------------|:-------:|:---:|:-------:|
| Hardware-backed key storage | ✅ | ✅ | ✅ |
| Biometric authentication | ✅ | ✅ | ✅ |
| Secure memory handling | ✅ | ✅ | ✅ |
| Post-quantum cryptography | ✅ | ✅ | ✅ |
| Code signing verification | ✅ | ✅ | ✅ |

---

## 6. Core Capabilities

### 6.1 User Management

| Capability | Description |
|------------|-------------|
| **Invitation-Based Registration** | Controlled onboarding via secure invitations |
| **Multi-Factor Authentication** | Support for WebAuthn, OIDC, SAML, Digital ID |
| **Multi-Tenant Support** | Users can belong to multiple organizations |
| **Role-Based Access** | Admin, member, and viewer roles |
| **Device Management** | Enroll, manage, and revoke device access |

### 6.2 File Management

| Capability | Description |
|------------|-------------|
| **End-to-End Encryption** | All files encrypted before leaving the device |
| **Hierarchical Folders** | Organize files in nested folder structures |
| **File Preview** | In-app preview for documents, images, PDFs, and videos |
| **Bulk Operations** | Multi-select for batch operations |
| **Offline Access** | Access cached files without connectivity |
| **Search** | Search files by name and metadata |

### 6.3 Sharing

| Capability | Description |
|------------|-------------|
| **Secure File Sharing** | Share files with cryptographic access control |
| **Folder Sharing** | Share entire folders with inherited permissions |
| **Permission Levels** | View, edit, and download permissions |
| **Share Expiration** | Time-limited access to shared content |
| **Share Revocation** | Immediately revoke access to shared content |
| **Audit Trail** | Track all sharing activity |

### 6.4 Key Recovery

| Capability | Description |
|------------|-------------|
| **Shamir Secret Sharing** | Threshold-based key recovery |
| **Trustee Selection** | Users designate trusted recovery contacts |
| **No Central Escrow** | Recovery keys never stored centrally |
| **Recovery Approval** | Multiple trustees must approve recovery |

### 6.5 Notifications

| Capability | Description |
|------------|-------------|
| **Push Notifications** | Real-time alerts for shares, comments, recovery |
| **Email Notifications** | Email alerts for important events |
| **In-App Notifications** | Notification center within applications |

---

## 7. PII Protection Service

### 7.1 Overview

A standalone service enabling users to work with AI assistants while protecting personal information in documents.

### 7.2 Capabilities

| Capability | Description |
|------------|-------------|
| **Document Redaction** | Automatically detect and redact PII from documents |
| **AI Chat Integration** | Query AI services about documents without exposing PII |
| **Conversation Persistence** | Maintain chat history with multiple documents |
| **Reversible Tokenization** | Replace PII with tokens that can be restored client-side |

### 7.3 PII Detection

| Category | Entity Types |
|----------|--------------|
| **Identity** | Names, NRIC, Passport numbers, MyKad |
| **Contact** | Email addresses, Phone numbers, Addresses |
| **Financial** | Bank accounts, Credit card numbers, Tax IDs |
| **Medical** | Medical record numbers, Health conditions |
| **Location** | Addresses, Postcodes, GPS coordinates |
| **Organization** | Company names, Registration numbers |

### 7.4 Detection Pipeline

- Pattern-based detection for known PII formats
- Machine learning-based named entity recognition
- Context-aware validation to reduce false positives
- Domain classification for specialized handling

### 7.5 Design Goals

| Goal | Target |
|------|--------|
| **Privacy** | 100% tokenization of detected PII before LLM processing |
| **Accuracy** | > 95% recall for sensitive data types |
| **Performance** | < 3 seconds per query |
| **Security** | Plaintext in memory < 5 seconds |

---

## 8. Integration Capabilities

### 8.1 Identity Providers

| Provider Type | Examples |
|---------------|----------|
| **WebAuthn/FIDO2** | Hardware authenticators, passkeys |
| **OIDC** | Azure AD, Google Workspace, Okta |
| **SAML** | Enterprise SSO providers |
| **National ID** | MyDigital ID (Malaysia) |

### 8.2 Storage Backends

| Provider Type | Examples |
|---------------|----------|
| **S3-Compatible** | AWS S3, Google Cloud Storage, Azure Blob, MinIO |

### 8.3 AI/LLM Providers (PII Service)

| Provider | Models |
|----------|--------|
| **OpenAI** | GPT-4, GPT-4o, GPT-3.5 |
| **Anthropic** | Claude 3 family |
| **Google** | Gemini Pro, Gemini Ultra |
| **Self-Hosted** | Ollama-compatible models |

### 8.4 Notifications

| Channel | Purpose |
|---------|---------|
| **Push** | Real-time mobile and desktop notifications |
| **Email** | SMTP-based email notifications |

---

## 9. Deployment & Operations

### 9.1 Deployment Options

| Option | Description |
|--------|-------------|
| **Container Orchestration** | Kubernetes, Docker Swarm |
| **Cloud Managed** | AWS, Google Cloud, Azure container services |
| **On-Premises** | Self-hosted deployment |

### 9.2 Infrastructure Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **API Servers** | 2 vCPU, 4GB RAM | 4 vCPU, 8GB RAM |
| **Database** | 2 vCPU, 8GB RAM, 100GB SSD | 4 vCPU, 16GB RAM, 500GB SSD |
| **Object Storage** | 100GB | Scalable |
| **PII Service** | 4 vCPU, 16GB RAM | 8 vCPU, 32GB RAM |

### 9.3 High Availability

| Component | Strategy |
|-----------|----------|
| **API Layer** | Horizontal scaling, stateless design |
| **Database** | Primary-replica replication |
| **Object Storage** | Cross-region replication |
| **Monitoring** | Health checks with auto-recovery |

### 9.4 Performance Targets

| Metric | Target |
|--------|--------|
| API Response Time (p95) | < 200ms |
| File Transfer Throughput | 100 MB/s per connection |
| Concurrent Users | 10,000+ |

### 9.5 Backup & Recovery

| Data Type | RPO | RTO |
|-----------|-----|-----|
| Database | 5 minutes | 1 hour |
| Object Storage | Real-time | 15 minutes |

### 9.6 Monitoring

- System performance metrics
- Structured logging
- Distributed tracing
- Configurable alerting
- Health check endpoints

---

## 10. Compliance & Standards

### 10.1 Cryptographic Standards

| Standard | Description |
|----------|-------------|
| NIST FIPS 203 | ML-KEM Key Encapsulation |
| NIST FIPS 204 | ML-DSA Digital Signatures |
| RFC 5649 | AES Key Wrap with Padding |
| RFC 5869 | HKDF Key Derivation |
| RFC 9106 | Argon2 Password Hashing |
| Malaysian KAZ | Post-quantum cryptography |

### 10.2 Security & Privacy Standards

| Standard | Relevance |
|----------|-----------|
| ISO 27001 | Information Security Management |
| SOC 2 Type II | Service Organization Controls |
| GDPR | Data protection (EU) |
| PDPA | Personal Data Protection Act (Malaysia) |

### 10.3 Audit Capabilities

- Immutable audit logs of all security-relevant operations
- User activity tracking
- File access logging
- Share grant/revoke history
- Device enrollment tracking
- Recovery request logging
- Exportable audit reports

---

## 11. Technical Requirements

### 11.1 Server Environment

| Requirement | Specification |
|-------------|---------------|
| **Operating System** | Linux (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| **Database** | PostgreSQL 14+ |
| **Object Storage** | S3-compatible API |
| **TLS** | 1.2 minimum, 1.3 recommended |

### 11.2 Network Requirements

| Requirement | Specification |
|-------------|---------------|
| **HTTPS** | Port 443 |
| **Bandwidth** | 1 Gbps minimum |
| **Latency** | < 50ms to clients |

### 11.3 Client Requirements

**Desktop:**
- macOS 11.0+
- Windows 10 (1903+)
- Linux: Ubuntu 20.04+

**Mobile:**
- iOS 15.0+
- Android 7.0+

### 11.4 Browser Support (Admin Portal)

| Browser | Minimum Version |
|---------|-----------------|
| Chrome | 90+ |
| Firefox | 88+ |
| Safari | 14+ |
| Edge | 90+ |

---

## Glossary

| Term | Definition |
|------|------------|
| **DEK** | Data Encryption Key - symmetric key for file encryption |
| **KEK** | Key Encryption Key - wraps DEKs at folder level |
| **KEM** | Key Encapsulation Mechanism - asymmetric key exchange |
| **ML-KEM** | Module-Lattice Key Encapsulation (NIST post-quantum) |
| **ML-DSA** | Module-Lattice Digital Signature Algorithm (NIST post-quantum) |
| **KAZ** | Malaysian post-quantum cryptographic standards |
| **PQC** | Post-Quantum Cryptography |
| **Shamir** | Secret sharing scheme for threshold-based recovery |
| **Zero-Knowledge** | Architecture where server cannot access plaintext |
| **Zero-Trust** | Security model where server is never trusted with keys |

---

**Document Control**

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | Feb 2026 | Simplified specification, removed architecture diagrams |
| 1.1.0 | Feb 2026 | Generalized specification |
| 1.0.0 | Feb 2026 | Initial specification |

---

*This document is confidential and intended for tender evaluation purposes only.*
