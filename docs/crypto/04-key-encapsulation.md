# Key Encapsulation Protocol Specification

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

Key Encapsulation Mechanisms (KEMs) are used in SecureSharing to securely share symmetric keys (DEKs and KEKs) between users without direct key exchange. This document specifies the dual-KEM approach using both NIST and Malaysian PQC algorithms.

## 2. KEM Operations

### 2.1 Key Generation

Each user generates two KEM key pairs during registration:

```
UserKEMKeyGen():
    // NIST ML-KEM-768
    (ml_pk, ml_sk) ← ML-KEM-768.KeyGen()

    // Malaysian KAZ-KEM
    (kaz_pk, kaz_sk) ← KAZ-KEM.KeyGen()

    return {
        publicKeys: {
            ml_kem: ml_pk,      // 1,184 bytes
            kaz_kem: kaz_pk     // 236 bytes
        },
        privateKeys: {
            ml_kem: ml_sk,      // 2,400 bytes (encrypted by MK)
            kaz_kem: kaz_sk     // 86 bytes (encrypted by MK)
        }
    }
```

### 2.2 Encapsulation (Sender Side)

When sharing a key with a recipient:

```
EncapsulateKey(key_to_share, recipient_ml_pk, recipient_kaz_pk):
    // Step 1: ML-KEM encapsulation
    (ct_ml, ss_ml) ← ML-KEM-768.Encapsulate(recipient_ml_pk)

    // Step 2: KAZ-KEM encapsulation
    (ct_kaz, ss_kaz) ← KAZ-KEM.Encapsulate(recipient_kaz_pk)

    // Step 3: Combine shared secrets
    combined_ss ← HKDF-SHA-384(
        ikm = ss_ml || ss_kaz,
        salt = "SecureSharing-KEM-Combine-v1",
        info = "combined-shared-secret",
        length = 32
    )

    // Step 4: Wrap the key with combined secret
    wrapped_key ← AES-256-KWP.Wrap(combined_ss, key_to_share)

    // Step 5: Clean up intermediate secrets
    ss_ml.zeroize()
    ss_kaz.zeroize()
    combined_ss.zeroize()

    return {
        wrappedKey: wrapped_key,
        kemCiphertexts: [
            { algorithm: "ML-KEM-768", ciphertext: ct_ml },
            { algorithm: "KAZ-KEM", ciphertext: ct_kaz }
        ]
    }
```

### 2.3 Decapsulation (Recipient Side)

When receiving a shared key:

```
DecapsulateKey(wrapped_key, kem_ciphertexts, recipient_ml_sk, recipient_kaz_sk):
    // Step 1: Find ciphertexts by algorithm
    ct_ml ← kem_ciphertexts.find(c => c.algorithm == "ML-KEM-768").ciphertext
    ct_kaz ← kem_ciphertexts.find(c => c.algorithm == "KAZ-KEM").ciphertext

    // Step 2: ML-KEM decapsulation
    ss_ml ← ML-KEM-768.Decapsulate(recipient_ml_sk, ct_ml)

    // Step 3: KAZ-KEM decapsulation
    ss_kaz ← KAZ-KEM.Decapsulate(recipient_kaz_sk, ct_kaz)

    // Step 4: Combine shared secrets (same derivation as sender)
    combined_ss ← HKDF-SHA-384(
        ikm = ss_ml || ss_kaz,
        salt = "SecureSharing-KEM-Combine-v1",
        info = "combined-shared-secret",
        length = 32
    )

    // Step 5: Unwrap the key
    key ← AES-256-KWP.Unwrap(combined_ss, wrapped_key)

    // Step 6: Clean up intermediate secrets
    ss_ml.zeroize()
    ss_kaz.zeroize()
    combined_ss.zeroize()

    return key
```

## 3. KEK Encapsulation for Owners

The root folder KEK is encapsulated directly for the owner (no parent KEK):

```
EncapsulateRootKEK(root_kek, owner_ml_pk, owner_kaz_pk):
    return EncapsulateKey(root_kek, owner_ml_pk, owner_kaz_pk)
```

### 3.1 Owner Key Access Structure

```typescript
interface OwnerKeyAccess {
  // The KEK wrapped with combined KEM shared secret
  wrappedKek: Uint8Array;

  // KEM ciphertexts for decapsulation
  kemCiphertexts: KEMCiphertext[];
}

interface KEMCiphertext {
  algorithm: "ML-KEM-768" | "KAZ-KEM";
  ciphertext: Uint8Array;
}
```

## 4. Sharing Keys with Recipients

### 4.1 File Sharing (DEK)

```
ShareFile(file_id, file_dek, recipient_id, permission, grantor_sign_keys):
    // Get recipient's public keys
    recipient_keys ← Server.getUserPublicKeys(recipient_id)

    // Encapsulate DEK for recipient
    encapsulation ← EncapsulateKey(
        file_dek,
        recipient_keys.ml_kem,
        recipient_keys.kaz_kem
    )

    // Create share grant
    grant ← {
        id: generateUUID(),
        resourceType: "file",
        resourceId: file_id,
        grantorId: current_user_id,
        granteeId: recipient_id,
        wrappedKey: encapsulation.wrappedKey,
        kemCiphertexts: encapsulation.kemCiphertexts,
        permission: permission,
        createdAt: current_timestamp
    }

    // Sign the grant
    grant.signature ← SignShareGrant(grant, grantor_sign_keys)

    return grant
```

### 4.2 Folder Sharing (KEK)

```
ShareFolder(folder_id, folder_kek, recipient_id, permission, recursive, grantor_sign_keys):
    // Get recipient's public keys
    recipient_keys ← Server.getUserPublicKeys(recipient_id)

    // Encapsulate KEK for recipient
    encapsulation ← EncapsulateKey(
        folder_kek,
        recipient_keys.ml_kem,
        recipient_keys.kaz_kem
    )

    // Create share grant
    grant ← {
        id: generateUUID(),
        resourceType: "folder",
        resourceId: folder_id,
        grantorId: current_user_id,
        granteeId: recipient_id,
        wrappedKey: encapsulation.wrappedKey,
        kemCiphertexts: encapsulation.kemCiphertexts,
        permission: permission,
        recursive: recursive,
        createdAt: current_timestamp
    }

    // Sign the grant
    grant.signature ← SignShareGrant(grant, grantor_sign_keys)

    return grant
```

## 5. Encapsulation Wire Format

### 5.1 KEM Ciphertext Structure

```
KEM Ciphertext Format:
┌─────────────────────────────────────────────────────────────────┐
│  Algorithm ID (1 byte)                                          │
│  ─────────────────────                                          │
│  0x01 = ML-KEM-768                                              │
│  0x02 = KAZ-KEM                                                 │
├─────────────────────────────────────────────────────────────────┤
│  Ciphertext Length (2 bytes, big-endian)                        │
├─────────────────────────────────────────────────────────────────┤
│  Ciphertext (variable)                                          │
│  • ML-KEM-768: 1,088 bytes                                      │
│  • KAZ-KEM-256: 354 bytes                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Encapsulated Key Package

```
Encapsulated Key Package Format:
┌─────────────────────────────────────────────────────────────────┐
│  Version (1 byte) = 0x01                                        │
├─────────────────────────────────────────────────────────────────┤
│  Number of KEM Ciphertexts (1 byte)                            │
├─────────────────────────────────────────────────────────────────┤
│  KEM Ciphertext 1 (ML-KEM-768)                                  │
│  ├── Algorithm ID: 0x01                                         │
│  ├── Length: 1,088                                              │
│  └── Ciphertext: [1,088 bytes]                                  │
├─────────────────────────────────────────────────────────────────┤
│  KEM Ciphertext 2 (KAZ-KEM-256)                                 │
│  ├── Algorithm ID: 0x02                                         │
│  ├── Length: 354                                                │
│  └── Ciphertext: [354 bytes]                                    │
├─────────────────────────────────────────────────────────────────┤
│  Wrapped Key Length (2 bytes, big-endian)                       │
├─────────────────────────────────────────────────────────────────┤
│  Wrapped Key (typically 40 bytes for 32-byte key)               │
└─────────────────────────────────────────────────────────────────┘
```

## 6. Share Grant Structure

```typescript
interface ShareGrant {
  // Identity
  id: string;                    // UUID

  // Resource being shared
  resourceType: "file" | "folder";
  resourceId: string;            // File or folder UUID

  // Parties
  grantorId: string;             // User who created the share
  granteeId: string;             // User receiving access

  // Cryptographic material
  wrappedKey: Uint8Array;        // DEK or KEK wrapped with combined KEM secret
  kemCiphertexts: KEMCiphertext[];  // One per algorithm

  // Access control
  permission: "read" | "write" | "admin";
  recursive: boolean;            // For folders only
  expiry?: string;               // ISO 8601 timestamp (optional)

  // Integrity
  signature: CombinedSignature;  // Grantor's signature
  createdAt: string;             // ISO 8601 timestamp
}

interface CombinedSignature {
  ml_dsa: Uint8Array;            // ML-DSA-65 signature
  kaz_sign: Uint8Array;          // KAZ-SIGN signature
}
```

## 7. Signature for Share Grants

### 7.1 Signed Data Format

```
SignedGrantData = SHA-256(CanonicalSerialize({
    resourceType,
    resourceId,
    grantorId,
    granteeId,
    wrappedKey,
    kemCiphertexts,    // IMPORTANT: Must include KEM ciphertexts
    permission,
    recursive,
    expiry,
    createdAt
}))
```

**Note**: The `kemCiphertexts` field MUST be included in the signature to prevent
an attacker from substituting their own KEM ciphertexts (which would let them
decrypt the wrapped key). See `05-signature-protocol.md` for canonical serialization rules.

### 7.2 Sign Operation

```
SignShareGrant(grant, grantor_sign_keys):
    signed_data ← SHA-256(SerializeGrantForSigning(grant))

    sig_ml ← ML-DSA-65.Sign(grantor_sign_keys.ml_dsa_sk, signed_data)
    sig_kaz ← KAZ-SIGN.Sign(grantor_sign_keys.kaz_sign_sk, signed_data)

    return {
        ml_dsa: sig_ml,
        kaz_sign: sig_kaz
    }
```

### 7.3 Verify Operation

```
VerifyShareGrant(grant, grantor_public_keys):
    signed_data ← SHA-256(SerializeGrantForSigning(grant))

    valid_ml ← ML-DSA-65.Verify(
        grantor_public_keys.ml_dsa_pk,
        signed_data,
        grant.signature.ml_dsa
    )

    valid_kaz ← KAZ-SIGN.Verify(
        grantor_public_keys.kaz_sign_pk,
        signed_data,
        grant.signature.kaz_sign
    )

    return valid_ml AND valid_kaz
```

## 8. Recipient Key Access Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              RECIPIENT ACCESSING SHARED FILE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Recipient authenticates                                     │
│     │                                                           │
│     ▼                                                           │
│  2. Fetch share grants for recipient                            │
│     grants ← Server.getSharesForUser(recipient_id)              │
│     │                                                           │
│     ▼                                                           │
│  3. For the desired file, find the share grant                  │
│     grant ← grants.find(g => g.resourceId == file_id)           │
│     │                                                           │
│     ▼                                                           │
│  4. Verify grant signature                                      │
│     grantor_keys ← Server.getUserPublicKeys(grant.grantorId)    │
│     if not VerifyShareGrant(grant, grantor_keys):               │
│         return Error("Invalid share grant")                     │
│     │                                                           │
│     ▼                                                           │
│  5. Check expiry                                                │
│     if grant.expiry and now() > grant.expiry:                   │
│         return Error("Share has expired")                       │
│     │                                                           │
│     ▼                                                           │
│  6. Decapsulate to get DEK                                      │
│     dek ← DecapsulateKey(                                       │
│         grant.wrappedKey,                                       │
│         grant.kemCiphertexts,                                   │
│         recipient_ml_sk,                                        │
│         recipient_kaz_sk                                        │
│     )                                                           │
│     │                                                           │
│     ▼                                                           │
│  7. Decrypt file with DEK                                       │
│     plaintext ← DecryptFile(encrypted_file, dek)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 9. Security Properties

### 9.1 Dual-Algorithm Security

Both KEM algorithms must be broken to recover the shared secret:
- If only ML-KEM is broken: attacker gets `ss_ml` but not `ss_kaz`
- If only KAZ-KEM is broken: attacker gets `ss_kaz` but not `ss_ml`
- HKDF combines both → both required

### 9.2 Forward Secrecy

Each share grant uses fresh KEM encapsulation:
- Even if recipient's private key is later compromised
- Historical share grants cannot be decrypted without the specific ciphertexts
- Re-sharing creates new ciphertexts

### 9.3 Non-Repudiation

Share grants are signed by the grantor:
- Recipient can prove who shared the file
- Server cannot forge share grants
- Audit trail of sharing actions

### 9.4 Access Revocation

Deleting a share grant revokes access:
- Recipient loses access to wrapped key
- No key re-encryption needed
- Immediate effect

## 10. Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| `E_KEM_ENCAP_FAILED` | Invalid public key | Verify key format |
| `E_KEM_DECAP_FAILED` | Invalid ciphertext or wrong key | Check share grant validity |
| `E_KEY_UNWRAP_FAILED` | Corrupted wrapped key | Request new share |
| `E_SIGNATURE_INVALID` | Tampered or forged grant | Reject and report |
| `E_GRANT_EXPIRED` | Share time limit exceeded | Request new share |
| `E_ALGORITHM_UNKNOWN` | Unsupported KEM algorithm | Update client |

## 11. Implementation Notes

### 11.1 Ciphertext Ordering

Always process KEM ciphertexts in deterministic order:
1. ML-KEM-768 first
2. KAZ-KEM second

This ensures `combined_ss` is identical on both sides.

### 11.2 Memory Handling

```typescript
// Example: TypeScript with manual cleanup
async function decapsulateKey(
  wrappedKey: Uint8Array,
  ciphertexts: KEMCiphertext[],
  mlSk: Uint8Array,
  kazSk: Uint8Array
): Promise<Uint8Array> {
  let ssMl: Uint8Array | null = null;
  let ssKaz: Uint8Array | null = null;
  let combined: Uint8Array | null = null;

  try {
    ssMl = await mlKem.decapsulate(mlSk, ciphertexts[0].ciphertext);
    ssKaz = await kazKem.decapsulate(kazSk, ciphertexts[1].ciphertext);
    combined = await hkdf(ssMl, ssKaz);
    return await aesKwp.unwrap(combined, wrappedKey);
  } finally {
    if (ssMl) ssMl.fill(0);
    if (ssKaz) ssKaz.fill(0);
    if (combined) combined.fill(0);
  }
}
```
