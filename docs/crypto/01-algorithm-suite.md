# Algorithm Suite Specification

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-02

## 1. Overview

SecureSharing uses a dual post-quantum cryptographic algorithm strategy combining:
- **NIST Standards**: ML-KEM-768 and ML-DSA-65
- **Malaysian Standards**: KAZ-KEM and KAZ-SIGN

This dual-algorithm approach provides defense-in-depth: both algorithm families must be broken to compromise security.

## 2. Algorithm Summary

| Purpose | NIST Algorithm | Malaysian Algorithm | Classical Fallback |
|---------|---------------|--------------------|--------------------|
| Key Encapsulation | ML-KEM-768 | KAZ-KEM | X25519 (optional) |
| Digital Signatures | ML-DSA-65 | KAZ-SIGN | Ed25519 (optional) |
| Symmetric Encryption | AES-256-GCM | AES-256-GCM | - |
| Key Derivation | HKDF-SHA-384 | HKDF-SHA-384 | - |
| Password-Based KDF | Argon2id (default) | Argon2id (default) | Bcrypt + HKDF |

## 3. Key Encapsulation Mechanisms (KEM)

### 3.1 ML-KEM-768 (NIST FIPS 203)

ML-KEM (Module-Lattice-Based Key Encapsulation Mechanism), formerly known as CRYSTALS-Kyber, is the NIST-standardized post-quantum KEM.

**Parameters (ML-KEM-768)**:
| Parameter | Value |
|-----------|-------|
| Security Level | NIST Level 3 (AES-192 equivalent) |
| Public Key Size | 1,184 bytes |
| Private Key Size | 2,400 bytes |
| Ciphertext Size | 1,088 bytes |
| Shared Secret Size | 32 bytes |

**Operations**:
```
KeyGen() → (pk, sk)
Encapsulate(pk) → (ct, ss)
Decapsulate(sk, ct) → ss
```

**Security Assumptions**:
- Module Learning With Errors (MLWE) problem
- Module Learning With Rounding (MLWR) problem

### 3.2 KAZ-KEM (Malaysian Standard)

KAZ-KEM is a post-quantum key encapsulation mechanism developed under Malaysian cryptographic standards.

**Parameters** (KAZ-KEM-256):
| Parameter | Value |
|-----------|-------|
| Security Level | 256-bit equivalent |
| Public Key Size | 236 bytes |
| Private Key Size | 86 bytes |
| Ciphertext Size | 354 bytes |
| Shared Secret Size | 32 bytes |

**All Security Levels**:
| Level | Public Key | Private Key | Ciphertext |
|-------|------------|-------------|------------|
| 128 | 108 bytes | 34 bytes | 162 bytes |
| 192 | 176 bytes | 64 bytes | 264 bytes |
| 256 | 236 bytes | 86 bytes | 354 bytes |

**Operations**:
```
KAZ_KEM_KeyGen() → (pk, sk)
KAZ_KEM_Encapsulate(pk) → (ct, ss)
KAZ_KEM_Decapsulate(sk, ct) → ss
```

### 3.3 Combined KEM Operation

When sharing keys, both KEMs are used in parallel:

```
CombinedEncapsulate(pk_ml, pk_kaz):
    (ct_ml, ss_ml) ← ML-KEM.Encapsulate(pk_ml)
    (ct_kaz, ss_kaz) ← KAZ-KEM.Encapsulate(pk_kaz)
    combined_ss ← HKDF-SHA-384(
        ikm = ss_ml || ss_kaz,
        salt = "SecureSharing-KEM-Combine-v1",
        info = "combined-shared-secret",
        length = 32
    )
    return (ct_ml, ct_kaz, combined_ss)

CombinedDecapsulate(sk_ml, sk_kaz, ct_ml, ct_kaz):
    ss_ml ← ML-KEM.Decapsulate(sk_ml, ct_ml)
    ss_kaz ← KAZ-KEM.Decapsulate(sk_kaz, ct_kaz)
    combined_ss ← HKDF-SHA-384(
        ikm = ss_ml || ss_kaz,
        salt = "SecureSharing-KEM-Combine-v1",
        info = "combined-shared-secret",
        length = 32
    )
    return combined_ss
```

**Security Property**: An attacker must break BOTH ML-KEM AND KAZ-KEM to recover the combined shared secret.

## 4. Digital Signature Schemes

### 4.1 ML-DSA-65 (NIST FIPS 204)

ML-DSA (Module-Lattice-Based Digital Signature Algorithm), formerly known as CRYSTALS-Dilithium, is the NIST-standardized post-quantum signature scheme.

**Parameters (ML-DSA-65)**:
| Parameter | Value |
|-----------|-------|
| Security Level | NIST Level 3 (AES-192 equivalent) |
| Public Key Size | 1,952 bytes |
| Private Key Size | 4,032 bytes |
| Signature Size | 3,309 bytes |

**Operations**:
```
KeyGen() → (pk, sk)
Sign(sk, message) → signature
Verify(pk, message, signature) → bool
```

**Security Assumptions**:
- Module Learning With Errors (MLWE) problem
- Module Short Integer Solution (MSIS) problem

### 4.2 KAZ-SIGN (Malaysian Standard)

KAZ-SIGN is a post-quantum digital signature scheme developed under Malaysian cryptographic standards.

**Parameters** (KAZ-SIGN-256):
| Parameter | Value |
|-----------|-------|
| Security Level | 256-bit equivalent |
| Public Key Size | 118 bytes |
| Private Key Size | 64 bytes |
| Signature Size | 356 bytes |
| Hash Function | SHA-512 |

**All Security Levels**:
| Level | Public Key | Private Key | Signature | Hash |
|-------|------------|-------------|-----------|------|
| 128 | 54 bytes | 32 bytes | 162 bytes | SHA-256 |
| 192 | 88 bytes | 50 bytes | 264 bytes | SHA-384 |
| 256 | 118 bytes | 64 bytes | 356 bytes | SHA-512 |

**Operations**:
```
KAZ_SIGN_KeyGen() → (pk, sk)
KAZ_SIGN_Sign(sk, message) → signature
KAZ_SIGN_Verify(pk, message, signature) → bool
```

### 4.3 Combined Signature Operation

For critical operations, both signature schemes are used:

```
CombinedSign(sk_ml, sk_kaz, message):
    sig_ml ← ML-DSA.Sign(sk_ml, message)
    sig_kaz ← KAZ-SIGN.Sign(sk_kaz, message)
    return {
        ml_dsa: sig_ml,
        kaz_sign: sig_kaz
    }

CombinedVerify(pk_ml, pk_kaz, message, signatures):
    valid_ml ← ML-DSA.Verify(pk_ml, message, signatures.ml_dsa)
    valid_kaz ← KAZ-SIGN.Verify(pk_kaz, message, signatures.kaz_sign)
    return valid_ml AND valid_kaz
```

**Security Property**: Both signatures must verify for the combined signature to be valid.

## 5. Symmetric Cryptography

### 5.1 AES-256-GCM

Used for file encryption and key wrapping.

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Key Size | 256 bits (32 bytes) |
| Nonce Size | 96 bits (12 bytes) |
| Tag Size | 128 bits (16 bytes) |
| Max Plaintext | 2^36 - 32 bytes per nonce |

**Operations**:
```
Encrypt(key, nonce, plaintext, aad) → ciphertext || tag
Decrypt(key, nonce, ciphertext || tag, aad) → plaintext | error
```

**Critical Requirements**:
- **Nonce MUST be unique** per (key, encryption) pair
- Never reuse a nonce with the same key
- Use cryptographically secure random nonce generation

### 5.2 AES-256-KWP (Key Wrap with Padding)

Used for wrapping DEKs and KEKs per RFC 5649.

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Key Size | 256 bits |
| Min Plaintext | 1 byte |
| Max Plaintext | 2^32 - 1 bytes |

**Operations**:
```
Wrap(kek, key_to_wrap) → wrapped_key
Unwrap(kek, wrapped_key) → key | error
```

## 6. Key Derivation

### 6.1 HKDF-SHA-384

Used for deriving keys from shared secrets and combining key material.

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Hash Function | SHA-384 |
| Output Length | Variable (typically 32 bytes) |

**Operations**:
```
HKDF-Extract(salt, ikm) → prk
HKDF-Expand(prk, info, length) → okm
HKDF(salt, ikm, info, length) → okm  // Combined
```

**Standard Salts and Info Strings**:
| Purpose | Salt | Info |
|---------|------|------|
| KEM Combine | `SecureSharing-KEM-Combine-v1` | `combined-shared-secret` |
| Master Key | `SecureSharing-MasterKey-v1` | `master-key-derivation` |
| KEK Derivation | `SecureSharing-KEK-v1` | `kek-{folder_id}` |
| DEK Derivation | `SecureSharing-DEK-v1` | `dek-{file_id}` |

### 6.2 Password-Based Key Derivation (Tiered KDF)

SecureSharing supports multiple KDF algorithms to accommodate varying client hardware capabilities. The KDF is used **client-side only** for deriving the master key encryption key from a vault password (OIDC/Digital ID flows).

#### 6.2.1 KDF Profile Selection

Clients select a KDF profile based on device capabilities. The profile identifier is stored alongside the `key_derivation_salt` so the correct KDF is used on subsequent logins.

| Profile | Algorithm | Memory/op | Target Devices | Security Level |
|---------|-----------|-----------|----------------|----------------|
| `argon2id-standard` | Argon2id | 64 MiB | Desktop, modern mobile (4+ GB RAM) | **Recommended** |
| `argon2id-low` | Argon2id | 19 MiB | Older mobile, low-RAM devices (2-4 GB RAM) | OWASP minimum |
| `bcrypt-hkdf` | Bcrypt + HKDF-SHA-384 | ~4 KB | Extremely constrained, legacy devices (< 2 GB RAM) | Acceptable |

> **Default**: Clients MUST use `argon2id-standard` unless device memory is insufficient. Downgrade is a client-side decision based on available RAM; the server does not influence KDF selection.

#### 6.2.2 Profile: `argon2id-standard` (Default)

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Variant | Argon2id |
| Memory | 64 MiB (65536 KiB) |
| Iterations | 3 |
| Parallelism | 4 |
| Output Length | 32 bytes |
| Salt Length | 16 bytes (random) |

**Operations**:
```
Argon2id(password, salt) → derived_key (32 bytes)
```

**Reference**: RFC 9106 — Argon2 Memory-Hard Function for Password Hashing and Proof-of-Work.

#### 6.2.3 Profile: `argon2id-low`

Reduced-memory Argon2id for devices that cannot allocate 64 MiB per KDF operation. Uses the OWASP-recommended minimum parameters.

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Variant | Argon2id |
| Memory | 19 MiB (19456 KiB) |
| Iterations | 4 |
| Parallelism | 4 |
| Output Length | 32 bytes |
| Salt Length | 16 bytes (random) |

**Operations**:
```
Argon2id(password, salt) → derived_key (32 bytes)
```

> **Note**: Iterations increased from 3 to 4 to partially compensate for reduced memory. This profile still provides memory-hard, GPU-resistant key derivation.

#### 6.2.4 Profile: `bcrypt-hkdf`

For extremely constrained devices where even 19 MiB allocation is not feasible. Uses Bcrypt for password hardening, then HKDF-SHA-384 to stretch the output to 32 bytes.

**Parameters**:
| Parameter | Value |
|-----------|-------|
| Algorithm | Bcrypt |
| Cost Factor | 13 (minimum 12, maximum 31) |
| Output Length | 24 bytes (Bcrypt native) |
| Salt Length | 16 bytes (random) |
| Stretch | HKDF-SHA-384 to 32 bytes |

**Operations**:
```
// Step 1: Bcrypt password hash (24-byte output)
bcrypt_hash = Bcrypt(password, salt, cost=13)

// Step 2: Stretch to 32 bytes via HKDF
derived_key = HKDF-SHA-384(
    ikm = bcrypt_hash,
    salt = "SecureSharing-Bcrypt-KDF-v1",
    info = "bcrypt-derived-key",
    length = 32
)
```

**Security considerations**:
- Bcrypt is NOT memory-hard (~4 KB per operation) — weaker against GPU/ASIC attacks than Argon2id
- Cost factor 13 produces ~250-500ms computation time on modern hardware
- The HKDF stretch step provides domain separation and consistent 32-byte output
- This profile SHOULD only be used when Argon2id profiles are not feasible

#### 6.2.5 KDF Profile Wire Format

The KDF profile is encoded in the first byte of `key_derivation_salt` stored on the server:

```
key_derivation_salt = [profile_byte] || [salt_bytes]

Profile byte values:
  0x01 = argon2id-standard (64 MiB, t=3, p=4)
  0x02 = argon2id-low      (19 MiB, t=4, p=4)
  0x03 = bcrypt-hkdf        (cost=13)
```

This allows the client to determine which KDF algorithm and parameters to use when deriving the key on login.

#### 6.2.6 Profile Migration

Users MAY upgrade their KDF profile when logging in from a more capable device:

1. Derive current key using stored profile
2. Decrypt Master Key
3. Re-derive new key using upgraded profile
4. Re-encrypt Master Key with new key
5. Update `key_derivation_salt` with new profile byte and new salt

Downgrade (e.g., `argon2id-standard` → `bcrypt-hkdf`) SHOULD require explicit user confirmation, as it reduces brute-force resistance.

## 7. Cryptographic Provider Interface

```typescript
/**
 * Abstract interface for cryptographic operations.
 * Implementations: NistProvider, KazProvider, HybridProvider
 */
interface CryptoProvider {
  readonly name: string;
  readonly version: string;

  // Key Encapsulation
  kemKeyGen(): Promise<KEMKeyPair>;
  kemEncapsulate(publicKey: Uint8Array): Promise<KEMEncapsulation>;
  kemDecapsulate(
    privateKey: Uint8Array,
    ciphertext: Uint8Array
  ): Promise<Uint8Array>;

  // Digital Signatures
  signKeyGen(): Promise<SignKeyPair>;
  sign(privateKey: Uint8Array, message: Uint8Array): Promise<Uint8Array>;
  verify(
    publicKey: Uint8Array,
    message: Uint8Array,
    signature: Uint8Array
  ): Promise<boolean>;
}

interface KEMKeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

interface SignKeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

interface KEMEncapsulation {
  ciphertext: Uint8Array;
  sharedSecret: Uint8Array;
}
```

## 8. Security Levels

| Algorithm | NIST Level | Classical Equivalent | Quantum Security |
|-----------|-----------|---------------------|------------------|
| ML-KEM-768 | Level 3 | AES-192 | ~150 qubits |
| ML-DSA-65 | Level 3 | AES-192 | ~150 qubits |
| KAZ-KEM-256 | Level 5* | AES-256 | ~200 qubits |
| KAZ-SIGN-256 | Level 5* | AES-256 | ~200 qubits |
| AES-256-GCM | Level 5 | AES-256 | AES-128 (Grover) |

*KAZ algorithms target NIST Level 5 equivalent security (256-bit classical).

## 9. Implementation Notes

### 9.1 Side-Channel Resistance
- All implementations MUST be constant-time
- No secret-dependent branches or memory access patterns
- Use verified implementations (liboqs, pqcrypto-rs)

### 9.2 Random Number Generation
- Use OS-provided CSPRNG:
  - Linux: `getrandom()`
  - macOS/iOS: `SecRandomCopyBytes()`
  - Windows: `BCryptGenRandom()` / `CryptGenRandom()`
  - Android: `/dev/urandom` or `SecureRandom`
- Never use `Math.random()` or similar PRNGs

### 9.3 Memory Handling
- Zero sensitive key material after use
- Use secure memory allocators where available
- Prevent swapping of key material to disk

### 9.4 Error Handling
- Decryption failures MUST NOT leak timing information
- Return generic errors, no detailed failure reasons
- Log security events without sensitive data

## 10. References

1. NIST FIPS 203: Module-Lattice-Based Key-Encapsulation Mechanism Standard
2. NIST FIPS 204: Module-Lattice-Based Digital Signature Standard
3. RFC 5649: Advanced Encryption Standard (AES) Key Wrap with Padding
4. RFC 5869: HMAC-based Extract-and-Expand Key Derivation Function (HKDF)
5. RFC 9106: Argon2 Memory-Hard Function for Password Hashing and Proof-of-Work
6. KAZ-KEM v1.0.0: Post-quantum KEM supporting NIST security levels 128/192/256
7. KAZ-SIGN v2.1.0: Post-quantum signature scheme with runtime level selection
8. OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
9. NIST SP 800-63B: Digital Identity Guidelines — Authentication and Lifecycle Management
