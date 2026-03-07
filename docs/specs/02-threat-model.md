# Threat Model

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the threat model for SecureSharing, identifying potential threats, attack vectors, and mitigations implemented in the system.

## 2. Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TRUST BOUNDARIES                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  FULLY TRUSTED                                                       │    │
│  │  • Native client application (signed, verified)                     │    │
│  │  • User's device (assumed secure, not rooted/jailbroken)           │    │
│  │  • Hardware security module (Secure Enclave, TPM, StrongBox)       │    │
│  │  • User's authentication credentials                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              ▲                                              │
│                              │ Trust Boundary                               │
│                              ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  SEMI-TRUSTED (Authentication only)                                 │    │
│  │  • Identity Providers (WebAuthn, OIDC, Digital ID)                  │    │
│  │  • IdP is trusted for authentication, NOT for key material          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              ▲                                              │
│                              │ Trust Boundary                               │
│                              ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  UNTRUSTED (Zero-Knowledge)                                         │    │
│  │  • SecureSharing Server                                             │    │
│  │  • Database                                                         │    │
│  │  • Object Storage                                                   │    │
│  │  • Network infrastructure                                           │    │
│  │  • Server administrators                                            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3. Adversary Models

### 3.1 Passive Network Attacker

**Capabilities**:
- Observe all network traffic
- Record encrypted communications
- Perform traffic analysis

**Mitigations**:
- TLS 1.3 for all communications
- Certificate pinning in mobile/desktop apps
- Perfect forward secrecy
- Metadata minimization

### 3.2 Compromised Server

**Capabilities**:
- Full access to database
- Full access to object storage
- Can modify server code
- Can impersonate server to clients

**Mitigations**:
- All file content encrypted client-side
- All metadata encrypted client-side
- Keys never sent to server in plaintext
- Client verifies signatures
- Client-side key derivation

### 3.3 Malicious Administrator

**Capabilities**:
- Database access
- Server configuration access
- Can deploy modified server code
- Cannot access client devices

**Mitigations**:
- Zero-knowledge architecture
- No plaintext keys on server
- Audit logging
- Code signing and verification
- Open source client for inspection

### 3.4 Quantum Attacker (Future)

**Capabilities**:
- Harvest encrypted traffic today
- Break classical cryptography later
- Shor's algorithm for RSA/ECC
- Grover's algorithm for symmetric

**Mitigations**:
- Post-quantum KEM (ML-KEM-768)
- Post-quantum signatures (ML-DSA-65)
- Dual algorithm (NIST + KAZ)
- AES-256 (quantum-resistant with Grover)

### 3.5 Insider Threat

**Capabilities**:
- Legitimate user access
- May have elevated permissions
- Can share credentials
- Social engineering

**Mitigations**:
- Per-user encryption keys
- Share grants are signed
- Audit trails
- Permission model
- Time-limited shares

## 4. Threat Analysis

### 4.1 Authentication Threats

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Credential theft | High | Medium | WebAuthn hardware binding |
| Session hijacking | High | Low | HttpOnly cookies, short expiry |
| Phishing | High | Medium | WebAuthn origin verification |
| Brute force | Medium | Low | Rate limiting, lockout |
| Replay attack | High | Low | Challenge-response, nonces |

### 4.2 Data Confidentiality Threats

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| Server compromise | Critical | Medium | Client-side encryption |
| Database leak | Critical | Medium | All data encrypted |
| Storage breach | Critical | Medium | Files are ciphertext only |
| Traffic interception | High | Low | TLS 1.3, certificate pinning |
| Key extraction | Critical | Low | Keys in memory only |

### 4.3 Data Integrity Threats

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| File modification | High | Low | Digital signatures |
| Share tampering | High | Low | Signed share grants |
| Metadata manipulation | Medium | Low | Encrypted metadata |
| Rollback attack | Medium | Low | Version tracking |

### 4.4 Availability Threats

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|------------|------------|
| DDoS attack | High | Medium | Rate limiting, CDN |
| Key loss | Critical | Low | Shamir recovery |
| Data deletion | High | Low | Soft delete, backups |
| Service outage | Medium | Medium | Redundancy, failover |

## 5. Attack Scenarios

### 5.1 Scenario: Compromised Database

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATTACK: DATABASE COMPROMISE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Attacker gains full database access                                        │
│                                                                              │
│  What attacker sees:                                                        │
│  ├── encrypted_master_key      → Ciphertext (cannot decrypt)               │
│  ├── encrypted_private_keys    → Ciphertext (cannot decrypt)               │
│  ├── public_keys               → Public (not sensitive)                     │
│  ├── encrypted_metadata        → Ciphertext (cannot decrypt)               │
│  ├── wrapped_dek / wrapped_kek → Ciphertext (cannot decrypt)               │
│  ├── share_grants              → Who shared with whom (metadata)           │
│  └── user_emails               → User identifiers (metadata)               │
│                                                                              │
│  What attacker CANNOT do:                                                   │
│  ✗ Decrypt any file content                                                │
│  ✗ Read file names                                                         │
│  ✗ Access user private keys                                                │
│  ✗ Forge shares (signature required)                                       │
│  ✗ Derive encryption keys                                                  │
│                                                                              │
│  What attacker CAN infer:                                                   │
│  • Number of users and files                                                │
│  • Sharing relationships (who shared with whom)                            │
│  • File sizes (encrypted size ≈ plaintext size)                            │
│  • Access patterns (timestamps)                                             │
│                                                                              │
│  RESULT: Confidentiality of file content PRESERVED                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Scenario: Malicious Server Code

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATTACK: MALICIOUS SERVER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Attacker deploys modified server code                                      │
│                                                                              │
│  Attack vectors:                                                            │
│  1. Intercept and modify API responses                                      │
│  2. Log all API requests                                                    │
│  3. Return false data (wrong public keys, etc.)                            │
│                                                                              │
│  Mitigations (Native Clients Only):                                         │
│  ✓ All crypto compiled into native app (not from server)                   │
│  ✓ All encryption keys derived client-side                                  │
│  ✓ Server never receives plaintext keys                                    │
│  ✓ Client verifies server responses (signatures)                           │
│  ✓ App distribution via signed packages (App Store, code signing)          │
│  ✓ Certificate pinning for API connections                                  │
│                                                                              │
│  Additional protections:                                                    │
│  • Keys stored in hardware security (Secure Enclave, TPM)                  │
│  • No server-delivered code (unlike web browsers)                          │
│  • Users can verify app integrity via platform checksums                   │
│                                                                              │
│  RESULT: Server cannot compromise client cryptography                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Scenario: Lost Device / Credentials

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATTACK: CREDENTIAL LOSS                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  User loses device with passkey                                             │
│                                                                              │
│  If attacker has device:                                                    │
│  • Cannot use passkey without biometric/PIN                                │
│  • PRF output requires successful authentication                           │
│  • Device lockout after failed attempts                                    │
│                                                                              │
│  Recovery process:                                                          │
│  1. User initiates recovery request                                         │
│  2. Identity verified by organization admin                                │
│  3. Trustees notified to approve                                           │
│  4. 3-of-5 trustees submit shares                                          │
│  5. User reconstructs master key                                           │
│  6. Old credentials revoked                                                │
│                                                                              │
│  Security properties:                                                       │
│  ✓ Single trustee cannot recover                                           │
│  ✓ Trustees never see plaintext master key                                 │
│  ✓ Shares re-encrypted for user's new keys                                 │
│  ✓ Old passkey invalidated                                                 │
│                                                                              │
│  RESULT: User can recover, attacker cannot access                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.4 Scenario: Quantum Computer Attack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ATTACK: QUANTUM COMPUTING                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Future quantum computer attempts to break cryptography                     │
│                                                                              │
│  Classical cryptography vulnerable:                                         │
│  ✗ RSA-2048 (broken by Shor's algorithm)                                   │
│  ✗ ECDH/ECDSA (broken by Shor's algorithm)                                 │
│                                                                              │
│  SecureSharing protections:                                                 │
│  ✓ ML-KEM-768 (NIST PQC standard)                                          │
│  ✓ ML-DSA-65 (NIST PQC standard)                                           │
│  ✓ KAZ-KEM (Malaysian PQC)                                                 │
│  ✓ KAZ-SIGN (Malaysian PQC)                                                │
│  ✓ AES-256-GCM (128-bit security vs Grover)                                │
│                                                                              │
│  Dual algorithm approach:                                                   │
│  • Both ML-KEM AND KAZ-KEM must be broken                                  │
│  • Combined shared secret: ss = HKDF(ss_ml || ss_kaz)                      │
│  • Defense in depth against algorithm-specific attacks                     │
│                                                                              │
│  RESULT: Protected against known quantum attacks                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 6. Security Controls

### 6.1 Preventive Controls

| Control | Purpose | Implementation |
|---------|---------|----------------|
| Client-side encryption | Prevent server access to plaintext | AES-256-GCM |
| PQC key encapsulation | Protect key exchange | ML-KEM + KAZ-KEM |
| Digital signatures | Prevent tampering | ML-DSA + KAZ-SIGN |
| Key hierarchy | Limit key exposure | DEK → KEK → PK chain |
| Tenant isolation | Prevent cross-tenant access | Cryptographic separation |

### 6.2 Detective Controls

| Control | Purpose | Implementation |
|---------|---------|----------------|
| Audit logging | Track all operations | Immutable audit log |
| Signature verification | Detect tampering | Client-side verification |
| Hash verification | Detect corruption | SHA-256 blob hashes |
| Counter verification | Detect passkey cloning | WebAuthn counter |

### 6.3 Corrective Controls

| Control | Purpose | Implementation |
|---------|---------|----------------|
| Key rotation | Recover from compromise | KEK rotation capability |
| Share revocation | Remove access | Delete + optional re-encrypt |
| Credential revocation | Invalidate compromised credentials | Session termination |
| Shamir recovery | Recover from key loss | 3-of-5 threshold |

## 7. Security Assumptions

### 7.1 Client Device

- User's device is not compromised at time of key generation
- Device secure enclave/TPM functions correctly (if used)
- Native app is installed from official sources (App Store, signed installer)
- User protects their device with PIN/biometric
- OS-level keychain/keystore is secure

### 7.2 Cryptographic Algorithms

- AES-256-GCM is secure for authenticated encryption
- ML-KEM-768 provides IND-CCA2 security
- ML-DSA-65 provides EUF-CMA security
- KAZ-KEM and KAZ-SIGN meet their security claims
- HKDF-SHA-384 is a secure PRF
- Argon2id is resistant to GPU/ASIC attacks

### 7.3 Identity Providers

- IdP correctly authenticates users
- IdP protects user credentials
- WebAuthn PRF extension is implemented correctly
- TLS certificates are valid and verified

## 8. Known Limitations

### 8.1 Metadata Leakage

The server can observe:
- User identities and email addresses
- Sharing relationships (who shared with whom)
- File sizes (encrypted size ≈ plaintext size)
- Access patterns (when files are accessed)
- Folder structure (parent-child relationships)

### 8.2 Client-Side Vulnerabilities

- Compromised native app installer could inject malicious code
- Physical device access could expose keys (mitigated by hardware security)
- Memory not guaranteed cleared on crash (mitigated by secure memory handling)
- Debugger/instrumentation attacks on rooted/jailbroken devices

### 8.3 Trust Requirements

- Initial client code must be delivered securely
- At least k-of-n trustees must be honest for recovery
- Organization admins have elevated trust for recovery approval

## 9. Residual Risks

| Risk | Severity | Probability | Acceptance |
|------|----------|-------------|------------|
| Metadata analysis | Low | High | Accepted (inherent to system) |
| All trustees collude | Critical | Very Low | Accepted (operational risk) |
| Both PQC algorithms broken | Critical | Very Low | Accepted (defense in depth) |
| User device compromised | Critical | Low | User responsibility |
| Malicious app distribution | High | Very Low | Mitigated by code signing |
| Rooted/jailbroken device | Medium | Low | User responsibility |

## 10. Security Testing

### 10.1 Required Tests

- [ ] Penetration testing (annual)
- [ ] Cryptographic audit
- [ ] Code security review
- [ ] Dependency vulnerability scanning
- [ ] Fuzzing of crypto operations

### 10.2 Continuous Monitoring

- Security vulnerability tracking
- Dependency updates
- Algorithm strength monitoring (PQC research)
- Incident response procedures
