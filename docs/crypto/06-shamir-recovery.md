# Shamir Secret Sharing Recovery Specification

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

Shamir Secret Sharing (SSS) enables splitting the Master Key (MK) into multiple shares such that:
- Any `k` shares can reconstruct the secret (threshold)
- Fewer than `k` shares reveal no information about the secret
- No single party (including the server) holds the complete key

This provides enterprise key recovery without centralized key escrow.

### 1.1 Why is Recovery Needed?

**Important**: The encrypted key bundle stored on the server cannot be decrypted without the **auth key**, which is derived from:
- **Passkey**: PRF output (hardware-bound to Secure Enclave/TPM)
- **OIDC**: Vault password (user's memory)

If the user loses their device (Passkey) or forgets their vault password, the auth key is **permanently lost**, making the encrypted key bundle useless despite being retrievable from the server.

```
Without Recovery:
─────────────────
Lost Device → Lost PRF → Lost Auth Key → Cannot Decrypt MK → DATA LOST FOREVER

With Shamir Recovery:
─────────────────────
Lost Device → Trustees provide shares → Reconstruct MK → Re-encrypt with new auth key → ACCESS RESTORED
```

Shamir recovery **bypasses the lost auth key** by reconstructing the Master Key directly from distributed shares, without ever needing the original auth key.

## 2. Parameters

### 2.1 Default Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `n` (total shares) | 5 | Total number of shares generated |
| `k` (threshold) | 3 | Minimum shares needed for recovery |
| Field | GF(2^256) | Galois field for polynomial arithmetic |
| Share size | 33 bytes | 1 byte index + 32 bytes value |

### 2.2 Configurable Options

Organizations can customize (within bounds):

| Parameter | Min | Max | Default |
|-----------|-----|-----|---------|
| `n` | 3 | 10 | 5 |
| `k` | 2 | n-1 | 3 |

**Constraint**: `2 <= k < n <= 10`

## 3. Share Generation

### 3.1 Algorithm

```
GenerateShares(secret, k, n):
    // Input validation
    assert len(secret) == 32
    assert 2 <= k < n <= 10

    // Generate random polynomial coefficients
    // P(x) = secret + a1*x + a2*x^2 + ... + a(k-1)*x^(k-1)
    coefficients ← [secret]
    for i in 1..(k-1):
        coefficients.append(CSPRNG(32 bytes))

    // Evaluate polynomial at points 1, 2, ..., n
    shares ← []
    for i in 1..n:
        x ← i
        y ← EvaluatePolynomial(coefficients, x)
        shares.append(Share { index: i, value: y })

    // Securely erase coefficients
    for coef in coefficients:
        coef.zeroize()

    return shares
```

### 3.2 Polynomial Evaluation (GF(2^256))

```
EvaluatePolynomial(coefficients, x):
    // Horner's method in GF(2^256)
    result ← coefficients[k-1]
    for i in (k-2)..0:
        result ← GF_Mul(result, x)
        result ← GF_Add(result, coefficients[i])
    return result
```

### 3.3 GF(2^256) Operations

Using the irreducible polynomial: `P(x) = x^256 + x^10 + x^5 + x^2 + 1`

```
GF_Add(a, b):
    return a XOR b

GF_Mul(a, b):
    // Carry-less multiplication with reduction
    result ← 0
    for i in 0..255:
        if bit(b, i) == 1:
            result ← GF_Add(result, a << i)
    return GF_Reduce(result)

GF_Reduce(x):
    // Reduce modulo P(x) = x^256 + x^10 + x^5 + x^2 + 1
    while degree(x) >= 256:
        x ← x XOR (P << (degree(x) - 256))
    return x
```

## 4. Secret Reconstruction

### 4.1 Algorithm (Lagrange Interpolation)

```
ReconstructSecret(shares):
    // Input validation
    assert len(shares) >= k
    assert all shares have distinct indices

    // Use exactly k shares
    selected ← shares[0:k]

    // Lagrange interpolation at x=0
    secret ← 0
    for i in 0..(k-1):
        xi ← selected[i].index
        yi ← selected[i].value

        // Compute Lagrange basis polynomial at x=0
        numerator ← 1
        denominator ← 1
        for j in 0..(k-1):
            if i ≠ j:
                xj ← selected[j].index
                numerator ← GF_Mul(numerator, xj)        // (0 - xj) = xj in GF
                denominator ← GF_Mul(denominator, GF_Sub(xi, xj))

        // li(0) = numerator / denominator
        li_0 ← GF_Mul(numerator, GF_Inv(denominator))

        // Add yi * li(0) to result
        secret ← GF_Add(secret, GF_Mul(yi, li_0))

    return secret
```

### 4.2 GF Inverse (Extended Euclidean Algorithm)

```
GF_Inv(a):
    // Find multiplicative inverse: a * a^(-1) = 1 mod P(x)
    // Using extended Euclidean algorithm
    ...
```

## 5. Share Distribution

### 5.1 Distribution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    SHARE DISTRIBUTION                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Generate shares from Master Key                             │
│     shares ← GenerateShares(MK, k=3, n=5)                       │
│                                                                  │
│  2. Encrypt each share for its trustee                          │
│     for (share, trustee) in zip(shares, trustees):              │
│         encrypted_share ← EncapsulateKey(                       │
│             share.value,                                        │
│             trustee.ml_kem_pk,                                  │
│             trustee.kaz_kem_pk                                  │
│         )                                                       │
│                                                                  │
│  3. Sign each encrypted share                                   │
│     signed_share ← CombinedSign(                                │
│         user_sign_keys,                                         │
│         encrypted_share || share.index || trustee_id            │
│     )                                                           │
│                                                                  │
│  4. Store on server (share never decrypted by server)           │
│     Server.storeRecoveryShare({                                 │
│         userId: current_user_id,                                │
│         trusteeId: trustee_id,                                  │
│         shareIndex: share.index,                                │
│         encryptedShare: encrypted_share,                        │
│         signature: signed_share                                 │
│     })                                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Trustee Types

| Type | Description | Example |
|------|-------------|---------|
| User Device | Another device owned by user | Backup phone |
| Org Admin | Organization administrator | Security officer |
| Trusted Contact | Designated colleague/family | Manager |
| Cold Storage | Offline printed backup | Paper in safe |
| Hardware Token | Dedicated security device | YubiKey |

### 5.3 Recovery Share Schema

```typescript
interface RecoveryShare {
  id: string;                    // UUID
  userId: string;                // User whose MK is split
  trusteeId: string;             // Trustee holding this share

  // Encrypted share
  shareIndex: number;            // 1-based index
  encryptedShare: {
    wrappedValue: Uint8Array;    // Share value encrypted for trustee
    kemCiphertexts: KEMCiphertext[];
  };

  // Signatures
  userSignature: CombinedSignature;     // User signing the share
  trusteeAcknowledgment?: CombinedSignature;  // Trustee confirming receipt

  // Metadata
  createdAt: string;             // ISO 8601
  acknowledgedAt?: string;       // When trustee confirmed
}
```

## 6. Recovery Flow

### 6.1 Recovery Request Initiation

```
┌─────────────────────────────────────────────────────────────────┐
│                 RECOVERY REQUEST INITIATION                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User loses access to Master Key                             │
│     (lost device, forgotten passkey, etc.)                      │
│                                                                  │
│  2. User authenticates via alternate method                     │
│     • Organization identity verification                         │
│     • Secondary authentication factor                            │
│     • Admin override with audit                                  │
│                                                                  │
│  3. User generates NEW key pairs                                │
│     new_keys ← UserKEMKeyGen() + UserSignKeyGen()               │
│                                                                  │
│  4. User creates recovery request                               │
│     request ← {                                                 │
│         userId: user_id,                                        │
│         newPublicKeys: new_keys.publicKeys,                     │
│         reason: "device_lost",                                  │
│         verificationMethod: "org_admin",                        │
│         requestedAt: current_timestamp                          │
│     }                                                           │
│                                                                  │
│  5. Server notifies trustees                                    │
│     Server.notifyTrustees(user_id, request.id)                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Trustee Approval Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRUSTEE APPROVAL                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  For each trustee:                                              │
│                                                                  │
│  1. Trustee receives notification                               │
│     "User X has requested key recovery"                         │
│                                                                  │
│  2. Trustee verifies identity out-of-band                       │
│     • Phone call                                                │
│     • Video conference                                          │
│     • In-person verification                                    │
│                                                                  │
│  3. Trustee decrypts their share                                │
│     share_value ← DecapsulateKey(                               │
│         encrypted_share.wrappedValue,                           │
│         encrypted_share.kemCiphertexts,                         │
│         trustee_ml_sk,                                          │
│         trustee_kaz_sk                                          │
│     )                                                           │
│                                                                  │
│  4. Trustee re-encrypts share for user's NEW keys               │
│     reencrypted ← EncapsulateKey(                               │
│         share_value,                                            │
│         request.newPublicKeys.ml_kem,                           │
│         request.newPublicKeys.kaz_kem                           │
│     )                                                           │
│                                                                  │
│  5. Trustee signs the approval                                  │
│     approval_sig ← CombinedSign(                                │
│         trustee_sign_keys,                                      │
│         request_id || share_index || reencrypted                │
│     )                                                           │
│                                                                  │
│  6. Submit to server                                            │
│     Server.submitRecoveryApproval({                             │
│         requestId: request_id,                                  │
│         trusteeId: trustee_id,                                  │
│         shareIndex: share_index,                                │
│         reencryptedShare: reencrypted,                          │
│         signature: approval_sig                                 │
│     })                                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 Master Key Reconstruction

```
┌─────────────────────────────────────────────────────────────────┐
│                  SECRET RECONSTRUCTION                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Once threshold (k) approvals received:                         │
│                                                                  │
│  1. User collects approved shares                               │
│     approvals ← Server.getRecoveryApprovals(request_id)         │
│     assert len(approvals) >= k                                  │
│                                                                  │
│  2. Verify each approval signature                              │
│     for approval in approvals:                                  │
│         trustee_keys ← Server.getUserPublicKeys(approval.trusteeId) │
│         assert VerifyApproval(approval, trustee_keys)           │
│                                                                  │
│  3. Decrypt each share                                          │
│     shares ← []                                                 │
│     for approval in approvals:                                  │
│         share_value ← DecapsulateKey(                           │
│             approval.reencryptedShare,                          │
│             user_new_ml_sk,                                     │
│             user_new_kaz_sk                                     │
│         )                                                       │
│         shares.append(Share {                                   │
│             index: approval.shareIndex,                         │
│             value: share_value                                  │
│         })                                                      │
│                                                                  │
│  4. Reconstruct Master Key                                      │
│     MK ← ReconstructSecret(shares)                              │
│                                                                  │
│  5. Verify MK by decrypting test data                           │
│     // User should have stored a verification blob              │
│     if not VerifyMK(MK, verification_blob):                     │
│         return Error("Reconstruction failed")                   │
│                                                                  │
│  6. Re-encrypt MK with new authentication                       │
│     new_encrypted_mk ← EncryptMK(MK, new_auth_secret)           │
│                                                                  │
│  7. Generate new Shamir shares                                  │
│     new_shares ← GenerateShares(MK, k, n)                       │
│     DistributeShares(new_shares, trustees)                      │
│                                                                  │
│  8. Update server                                               │
│     Server.updateUserKeys({                                     │
│         encryptedMK: new_encrypted_mk,                          │
│         publicKeys: new_keys.publicKeys,                        │
│         encryptedPrivateKeys: EncryptPrivateKeys(new_keys, MK)  │
│     })                                                          │
│                                                                  │
│  9. Invalidate old authentication                               │
│     Server.revokeOldCredentials(user_id)                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 7. Security Properties

### 7.1 Information-Theoretic Security

With fewer than `k` shares:
- No information about secret is revealed
- Not computationally secure, but unconditionally secure
- Attacker gains zero bits of information

### 7.2 Share Independence

Each share is cryptographically independent:
- Compromising one share doesn't help with others
- Shares can be stored with different security levels
- Trustees don't need to trust each other

### 7.3 Verification

MK reconstruction can be verified:
- Store encrypted verification blob during setup
- After reconstruction, decrypt and verify
- Prevents accepting incorrect reconstruction

### 7.4 Forward Secrecy After Recovery

After successful recovery:
- New Shamir shares are generated
- Old shares are cryptographically invalid
- Previous trustees' shares cannot be reused

## 8. Tenant Configuration

### 8.1 Organization Recovery Policy

```typescript
interface RecoveryPolicy {
  // Shamir parameters
  threshold: number;             // k
  totalShares: number;           // n

  // Trustee requirements
  requiredTrusteeTypes: {
    orgAdmin: number;            // Min org admins
    userDevice: number;          // Min user devices
    externalTrustee: number;     // Min external trustees
  };

  // Approval requirements
  verificationMethods: ("org_admin" | "video_call" | "in_person")[];
  approvalExpiryHours: number;   // Time limit for approvals
  cooldownHours: number;         // Wait time before recovery

  // Audit
  notifyOnRecovery: string[];    // Email addresses
  requireJustification: boolean;
}
```

### 8.2 Default Enterprise Policy

```typescript
const DEFAULT_ENTERPRISE_POLICY: RecoveryPolicy = {
  threshold: 3,
  totalShares: 5,
  requiredTrusteeTypes: {
    orgAdmin: 2,
    userDevice: 1,
    externalTrustee: 0
  },
  verificationMethods: ["org_admin", "video_call"],
  approvalExpiryHours: 72,
  cooldownHours: 24,
  notifyOnRecovery: ["security@company.com"],
  requireJustification: true
};
```

## 9. Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| `E_INSUFFICIENT_SHARES` | Fewer than k approvals | Wait for more trustees |
| `E_RECONSTRUCTION_FAILED` | Invalid shares | Verify share integrity |
| `E_APPROVAL_EXPIRED` | Trustee took too long | Request new approval |
| `E_TRUSTEE_UNAVAILABLE` | Trustee cannot respond | Use alternate trustee |
| `E_VERIFICATION_FAILED` | Wrong MK reconstructed | Check share indices |

## 10. Audit Trail

All recovery operations are logged:

```typescript
interface RecoveryAuditEvent {
  eventType:
    | "recovery_requested"
    | "trustee_notified"
    | "approval_submitted"
    | "threshold_reached"
    | "reconstruction_attempted"
    | "reconstruction_succeeded"
    | "reconstruction_failed"
    | "credentials_updated";

  userId: string;
  requestId: string;
  trusteeId?: string;
  timestamp: string;
  ipAddress: string;
  userAgent: string;
  additionalData?: Record<string, unknown>;
}
```

## 11. Implementation Notes

### 11.1 Polynomial Coefficient Security

```rust
// Rust example: Secure coefficient generation
fn generate_coefficients(secret: &[u8; 32], k: usize) -> Vec<[u8; 32]> {
    let mut coefficients = Vec::with_capacity(k);
    coefficients.push(*secret);

    for _ in 1..k {
        let mut coef = [0u8; 32];
        getrandom::getrandom(&mut coef).expect("RNG failed");
        coefficients.push(coef);
    }

    coefficients
}
```

### 11.2 Share Validation

```typescript
function validateShares(shares: Share[]): void {
  // Check for duplicate indices
  const indices = shares.map(s => s.index);
  if (new Set(indices).size !== indices.length) {
    throw new Error("Duplicate share indices");
  }

  // Check index bounds
  for (const share of shares) {
    if (share.index < 1 || share.index > 10) {
      throw new Error("Invalid share index");
    }
  }

  // Check value length
  for (const share of shares) {
    if (share.value.length !== 32) {
      throw new Error("Invalid share value length");
    }
  }
}
```
