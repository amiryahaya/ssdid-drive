# Recovery Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the key recovery flow using Shamir Secret Sharing. Recovery enables users to regain access to their encrypted data when they lose their primary authentication method.

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 2. Why Recovery is Needed

A common question: *"If the encrypted key bundle is stored on the server, why do we need recovery?"*

**The key bundle is encrypted.** Retrieving it from the server is not enough—you need the **auth key** to decrypt it.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    THE ENCRYPTION CHAIN                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐     │
│  │   Auth Key      │─────▶│   Master Key    │─────▶│  Private Keys   │     │
│  │                 │      │                 │      │  + Root KEK     │     │
│  │  (decrypts)     │      │  (decrypts)     │      │                 │     │
│  └─────────────────┘      └─────────────────┘      └─────────────────┘     │
│          │                                                                  │
│          │                                                                  │
│  ┌───────┴───────────────────────────────────────────────────────────┐     │
│  │  Auth Key Source:                                                  │     │
│  │                                                                    │     │
│  │  • Passkey (WebAuthn):                                            │     │
│  │    └─ Auth Key = HKDF(PRF_output)                                 │     │
│  │    └─ PRF_output is HARDWARE-BOUND (Secure Enclave, TPM)         │     │
│  │    └─ If device lost → PRF_output is UNRECOVERABLE               │     │
│  │                                                                    │     │
│  │  • OIDC + Vault Password:                                         │     │
│  │    └─ Auth Key = Argon2id(vault_password)                         │     │
│  │    └─ If password forgotten → Auth Key is UNRECOVERABLE          │     │
│  │                                                                    │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Scenario: Lost Device with Passkey

| Step | What Happens |
|------|--------------|
| 1 | User loses phone containing Passkey |
| 2 | User logs in on new device |
| 3 | Server returns encrypted key bundle ✓ |
| 4 | Client needs auth key to decrypt... |
| 5 | Auth key came from Passkey PRF output |
| 6 | PRF output was bound to lost device's Secure Enclave |
| 7 | **Cannot derive auth key → Cannot decrypt Master Key** |
| 8 | **All data inaccessible** |

### How Shamir Recovery Solves This

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    RECOVERY BYPASSES AUTH KEY                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Normal Login:                                                              │
│  ─────────────                                                              │
│  Passkey PRF ──▶ Auth Key ──▶ Decrypt Master Key ──▶ Access Files          │
│       ▲                                                                     │
│       │                                                                     │
│       ✗ BLOCKED (device lost)                                              │
│                                                                              │
│  Recovery Path:                                                             │
│  ──────────────                                                             │
│  Shamir Shares (from trustees) ──▶ Reconstruct Master Key ──▶ Access Files │
│                                           │                                 │
│                                           ▼                                 │
│                                    Re-encrypt MK with                       │
│                                    NEW Passkey's PRF                        │
│                                                                              │
│  Result: User regains access without needing the lost auth key             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Recovery Scenarios Summary

| Scenario | Server Has Key Bundle | User Can Decrypt | Recovery Needed |
|----------|----------------------|------------------|-----------------|
| Normal login | ✓ | ✓ (have auth key) | No |
| Lost Passkey device | ✓ | ✗ (PRF gone) | **Yes** |
| Forgot vault password | ✓ | ✗ (can't derive) | **Yes** |
| Corrupted local storage | ✓ | ✓ (re-download) | No |

**Key Point**: The encrypted key bundle on the server is protected by zero-knowledge encryption. Without the auth key (which only exists on the user's device or in their memory), it cannot be decrypted. Shamir recovery provides a secure backup path to reconstruct the Master Key directly, bypassing the lost auth key.

## 3. Prerequisites

- User has previously set up recovery shares (distributed to trustees)
- At least `k` of `n` trustees are available (default: 3 of 5)
- User can verify their identity through alternative means
- User has access to a device that can generate new keys

## 4. Recovery Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RECOVERY FLOW                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│  │ User    │  │ Client  │  │ Server  │  │Trustees │  │  Admin  │           │
│  │ (Lost)  │  │         │  │         │  │(1,2,3..)│  │         │           │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘           │
│       │            │            │            │            │                  │
│       │  1. Initiate Recovery   │            │            │                  │
│       │───────────▶│            │            │            │                  │
│       │            │            │            │            │                  │
│       │            │  2. Request Recovery    │            │                  │
│       │            │───────────▶│            │            │                  │
│       │            │            │            │            │                  │
│       │            │            │  3. Verify Identity     │                  │
│       │            │            │───────────────────────▶│                  │
│       │            │            │            │            │                  │
│       │            │            │  4. Identity Confirmed  │                  │
│       │            │            │◀───────────────────────│                  │
│       │            │            │            │            │                  │
│       │            │            │  5. Notify Trustees     │                  │
│       │            │            │───────────▶│            │                  │
│       │            │            │            │            │                  │
│       │  6. Generate new key pair            │            │                  │
│       │◀──────────│            │            │            │                  │
│       │            │            │            │            │                  │
│       │            │  7. Submit new public keys          │                  │
│       │            │───────────▶│            │            │                  │
│       │            │            │            │            │                  │
│       │            │            │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─        │
│       │            │            │                                            │
│       │            │            │  TRUSTEE APPROVAL LOOP (for each trustee) │
│       │            │            │                                            │
│       │            │            │            │  8. View pending request      │
│       │            │            │◀───────────│                               │
│       │            │            │            │                               │
│       │            │            │            │  ┌────────────────────────┐   │
│       │            │            │            │  │ 9. TRUSTEE OPERATIONS  │   │
│       │            │            │            │  │                        │   │
│       │            │            │            │  │ a. Decrypt own share   │   │
│       │            │            │            │  │    (using trustee's    │   │
│       │            │            │            │  │     private keys)      │   │
│       │            │            │            │  │                        │   │
│       │            │            │            │  │ b. Re-encrypt share    │   │
│       │            │            │            │  │    for user's NEW      │   │
│       │            │            │            │  │    public keys         │   │
│       │            │            │            │  │                        │   │
│       │            │            │            │  │ c. Sign approval       │   │
│       │            │            │            │  │                        │   │
│       │            │            │            │  └────────────────────────┘   │
│       │            │            │            │                               │
│       │            │            │  10. Submit re-encrypted share            │
│       │            │            │◀───────────│                               │
│       │            │            │                                            │
│       │            │            │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─        │
│       │            │            │            │            │                  │
│       │            │            │  11. Threshold Reached (3 of 5)           │
│       │            │            │            │            │                  │
│       │            │  12. Notify threshold reached       │                  │
│       │            │◀───────────│            │            │                  │
│       │            │            │            │            │                  │
│       │            │  13. Collect approved shares        │                  │
│       │            │───────────▶│            │            │                  │
│       │            │            │            │            │                  │
│       │            │  14. Return encrypted shares        │                  │
│       │            │◀───────────│            │            │                  │
│       │            │            │            │            │                  │
│       │            │  ┌────────────────────────────────┐ │                  │
│       │            │  │ 15. CLIENT-SIDE RECONSTRUCTION │ │                  │
│       │            │  │                                │ │                  │
│       │            │  │ a. Decrypt each share          │ │                  │
│       │            │  │    (using new private keys)    │ │                  │
│       │            │  │                                │ │                  │
│       │            │  │ b. Reconstruct Master Key      │ │                  │
│       │            │  │    via Shamir interpolation    │ │                  │
│       │            │  │                                │ │                  │
│       │            │  │ c. Decrypt old private keys    │ │                  │
│       │            │  │    (using recovered MK)        │ │                  │
│       │            │  │                                │ │                  │
│       │            │  │ d. Re-encrypt MK with new      │ │                  │
│       │            │  │    auth key                    │ │                  │
│       │            │  │                                │ │                  │
│       │            │  └────────────────────────────────┘ │                  │
│       │            │            │            │            │                  │
│       │            │  16. Complete Recovery              │                  │
│       │            │───────────▶│            │            │                  │
│       │            │            │            │            │                  │
│       │            │            │  ┌─────────────────┐    │                  │
│       │            │            │  │ 17. Finalize    │    │                  │
│       │            │            │  │ - Update keys   │    │                  │
│       │            │            │  │ - Revoke old    │    │                  │
│       │            │            │  │   credentials   │    │                  │
│       │            │            │  │ - Audit log     │    │                  │
│       │            │            │  └─────────────────┘    │                  │
│       │            │            │            │            │                  │
│       │            │  18. New Session Token              │                  │
│       │            │◀───────────│            │            │                  │
│       │            │            │            │            │                  │
│       │  19. Access Restored    │            │            │                  │
│       │◀──────────│            │            │            │                  │
│       │            │            │            │            │                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5. Detailed Steps

### 5.1 Step 1-7: Initiate Recovery Request

The recovery request combines key generation, verification, and submission in a single flow:

```typescript
/**
 * Recovery reason enum - must match data model
 */
type RecoveryReason = 'device_lost' | 'passkey_unavailable' | 'credential_reset' | 'admin_request';

/**
 * Verification methods for identity confirmation
 */
interface VerificationRequest {
  method: 'org_admin' | 'video_call' | 'in_person' | 'backup_codes';

  // For org_admin
  admin_id?: string;
  verification_code?: string;

  // For backup_codes
  backup_code?: string;
}

/**
 * Complete recovery initiation flow
 *
 * 1. Generate new PQC key pairs (client-side)
 * 2. Submit recovery request with verification and new public keys
 */
async function initiateRecovery(
  tenantId: string,
  email: string,
  reason: RecoveryReason,
  verification: VerificationRequest
): Promise<RecoveryInitiation> {

  // Step 6: Generate new PQC key pairs FIRST (client-side, before request)
  const mlKemKeyPair = await cryptoProvider.kemKeyGen('ML-KEM-768');
  const mlDsaKeyPair = await cryptoProvider.signKeyGen('ML-DSA-65');
  const kazKemKeyPair = await cryptoProvider.kemKeyGen('KAZ-KEM');
  const kazSignKeyPair = await cryptoProvider.signKeyGen('KAZ-SIGN');

  // Store private keys temporarily (in memory only)
  // These will be needed later to decrypt re-encrypted shares
  recoveryState.newPrivateKeys = {
    ml_kem: mlKemKeyPair.privateKey,
    ml_dsa: mlDsaKeyPair.privateKey,
    kaz_kem: kazKemKeyPair.privateKey,
    kaz_sign: kazSignKeyPair.privateKey
  };

  // Step 2 + 3-4 + 7: Submit recovery request with verification AND new keys
  // The API accepts all this in a single POST request
  const response = await fetch('/api/v1/recovery/requests', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tenant_id: tenantId,
      email: email,
      reason: reason,
      verification: verification,
      new_public_keys: {
        ml_kem: base64Encode(mlKemKeyPair.publicKey),
        ml_dsa: base64Encode(mlDsaKeyPair.publicKey),
        kaz_kem: base64Encode(kazKemKeyPair.publicKey),
        kaz_sign: base64Encode(kazSignKeyPair.publicKey)
      }
    })
  });

  if (!response.ok) {
    const error = await response.json();
    // Clear private keys on failure
    Object.values(recoveryState.newPrivateKeys).forEach(k => k.fill(0));
    recoveryState.newPrivateKeys = null;
    throw new RecoveryError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  // data contains:
  // - request: { id, user_id, status, reason, approvals_required, approvals_received, expires_at }
  // - trustees_notified: number
  // - temporary_token: string (for polling status)
  return data;
}
```

> **Note**: The API combines verification and key submission into a single request.
> Trustees are notified automatically after the request is created.

### 5.2 Step 8-10: Trustee Approval Process

```typescript
// Trustee's view: List pending recovery requests
async function getTrusteesPendingRequests(): Promise<PendingRecoveryRequest[]> {
  const response = await fetch('/api/v1/recovery/trustee/pending', {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  return (await response.json()).data.items;
}

// Trustee approves recovery
async function approveRecoveryRequest(
  requestId: string,
  myShare: EncryptedShare,
  userNewPublicKeys: PublicKeys
): Promise<void> {

  const keys = keyManager.getKeys();

  // 9a. Decrypt my share (using my private keys)
  const decryptedShare = await decapsulateKey(
    myShare.encrypted_share,
    {
      ml_kem: keys.privateKeys.ml_kem,
      kaz_kem: keys.privateKeys.kaz_kem
    }
  );

  // 9b. Re-encrypt share for user's NEW public keys
  const { wrappedKey, kemCiphertexts } = await encapsulateKey(
    decryptedShare,
    {
      ml_kem: base64Decode(userNewPublicKeys.ml_kem),
      kaz_kem: base64Decode(userNewPublicKeys.kaz_kem)
    }
  );

  // Clear decrypted share
  decryptedShare.fill(0);

  // 9c. Sign approval
  const signaturePayload = canonicalize({
    request_id: requestId,
    share_index: myShare.share_index,
    wrapped_value: base64Encode(wrappedKey),
    kem_ciphertexts: kemCiphertexts,
    approved_at: new Date().toISOString()
  });

  const signature = await combinedSign(
    {
      ml_dsa: keys.privateKeys.ml_dsa,
      kaz_sign: keys.privateKeys.kaz_sign
    },
    signaturePayload
  );

  // 10. Submit approval
  const response = await fetch(`/api/v1/recovery/requests/${requestId}/approve`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      share_index: myShare.share_index,
      reencrypted_share: {
        wrapped_value: base64Encode(wrappedKey),
        kem_ciphertexts: kemCiphertexts
      },
      signature
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new RecoveryError(error.error.code, error.error.message);
  }
}
```

### 5.3 Step 11-14: Threshold Reached, Collect Shares

```typescript
async function checkRecoveryStatus(
  requestId: string,
  tempToken: string
): Promise<RecoveryStatus> {

  const response = await fetch(`/api/v1/recovery/requests/${requestId}`, {
    headers: {
      'Authorization': `Bearer ${tempToken}`
    }
  });

  const { data } = await response.json();

  return {
    status: data.status,
    approvalsRequired: data.approvals_required,
    approvalsReceived: data.approvals_received,
    thresholdReached: data.approvals_received >= data.approvals_required
  };
}

async function collectApprovedShares(
  requestId: string,
  tempToken: string
): Promise<ApprovedShare[]> {

  const response = await fetch(`/api/v1/recovery/requests/${requestId}/shares`, {
    headers: {
      'Authorization': `Bearer ${tempToken}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new RecoveryError(error.error.code, error.error.message);
  }

  const { data } = await response.json();
  return data.approvals;
}
```

### 5.4 Step 15: Client-Side Reconstruction

```typescript
async function reconstructMasterKey(
  approvedShares: ApprovedShare[],
  newPrivateKeys: PrivateKeys
): Promise<Uint8Array> {

  // 15a. Decrypt each share using new private keys
  const decryptedShares: ShamirShare[] = [];

  for (const approval of approvedShares) {
    const shareValue = await decapsulateKey(
      approval.reencrypted_share,
      {
        ml_kem: newPrivateKeys.ml_kem,
        kaz_kem: newPrivateKeys.kaz_kem
      }
    );

    decryptedShares.push({
      index: approval.share_index,
      value: shareValue
    });
  }

  // 15b. Reconstruct Master Key via Shamir interpolation
  const masterKey = shamirReconstruct(decryptedShares);

  // Clear individual shares
  for (const share of decryptedShares) {
    share.value.fill(0);
  }

  return masterKey;
}

function shamirReconstruct(shares: ShamirShare[]): Uint8Array {
  // GF(2^256) Lagrange interpolation
  // See shamir-recovery.md for full algorithm

  const result = new Uint8Array(32);

  for (const share_i of shares) {
    let lagrangeCoeff = gfOne();

    for (const share_j of shares) {
      if (share_i.index !== share_j.index) {
        // λ_i = Π (x_j / (x_j - x_i)) for j ≠ i
        const xj = gfFromInt(share_j.index);
        const xi = gfFromInt(share_i.index);
        const num = xj;
        const denom = gfSub(xj, xi);
        lagrangeCoeff = gfMul(lagrangeCoeff, gfDiv(num, denom));
      }
    }

    // result += λ_i * y_i
    const term = gfMul(lagrangeCoeff, share_i.value);
    gfAddInPlace(result, term);
  }

  return result;
}
```

### 5.5 Step 15c-d: Decrypt Old Keys and Re-encrypt MK

```typescript
async function completeRecovery(
  requestId: string,
  tempToken: string,
  masterKey: Uint8Array,
  newPrivateKeys: PrivateKeys,
  keyBundle: EncryptedKeyBundle,
  newAuthKeyMaterial: Uint8Array  // From new passkey
): Promise<Session> {

  // 15c. Decrypt old private keys using recovered MK
  const oldPrivateKeys = {
    ml_kem: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.ml_kem),
    ml_dsa: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.ml_dsa),
    kaz_kem: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.kaz_kem),
    kaz_sign: await decryptPrivateKey(masterKey, keyBundle.encrypted_private_keys.kaz_sign)
  };

  // 15d. Re-encrypt MK with new auth key (from new passkey)
  const newAuthKey = await hkdfDerive(newAuthKeyMaterial, "master-key-encryption", 32);
  const newMkNonce = crypto.getRandomValues(new Uint8Array(12));
  const newEncryptedMk = await aesGcmEncrypt(newAuthKey, newMkNonce, masterKey);

  // Re-encrypt private keys with MK (for storage)
  const newEncryptedPrivateKeys = {
    ml_kem: await encryptPrivateKey(masterKey, oldPrivateKeys.ml_kem),
    ml_dsa: await encryptPrivateKey(masterKey, oldPrivateKeys.ml_dsa),
    kaz_kem: await encryptPrivateKey(masterKey, oldPrivateKeys.kaz_kem),
    kaz_sign: await encryptPrivateKey(masterKey, oldPrivateKeys.kaz_sign)
  };

  // Clear sensitive data
  masterKey.fill(0);
  newAuthKey.fill(0);
  Object.values(oldPrivateKeys).forEach(k => k.fill(0));

  // Submit completion to server
  const response = await fetch(`/api/v1/recovery/requests/${requestId}/complete`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${tempToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      encrypted_master_key: base64Encode(newEncryptedMk),
      mk_nonce: base64Encode(newMkNonce),
      encrypted_private_keys: newEncryptedPrivateKeys
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new RecoveryError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  return {
    token: data.session.token,
    expiresAt: data.session.expires_at,
    recoverySharesRegenerationRequired: data.recovery_shares_regeneration_required
  };
}
```

## 6. Post-Recovery Actions

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    POST-RECOVERY REQUIREMENTS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  After successful recovery:                                                 │
│                                                                              │
│  1. OLD CREDENTIALS REVOKED                                                 │
│     ├── Old passkeys invalidated                                            │
│     ├── Old sessions terminated                                             │
│     └── Audit log entry created                                             │
│                                                                              │
│  2. RECOVERY SHARES REGENERATION REQUIRED                                   │
│     ├── Old shares are now known to trustees                                │
│     ├── Must generate new Shamir split                                      │
│     └── Distribute to same or new trustees                                  │
│                                                                              │
│  3. SECURITY REVIEW RECOMMENDED                                             │
│     ├── Review recent access logs                                           │
│     ├── Verify no unauthorized changes                                      │
│     └── Consider file re-encryption if compromised                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Regenerate Recovery Shares

```typescript
async function regenerateRecoveryShares(
  trustees: TrusteeInfo[]
): Promise<void> {

  const keys = keyManager.getKeys();
  const threshold = 3;

  // Generate new Shamir shares
  const shares = shamirSplit(keys.masterKey, trustees.length, threshold);

  // Encrypt each share for its trustee
  const shareBundle = await Promise.all(
    trustees.map(async (trustee, i) => {
      const { wrappedKey, kemCiphertexts } = await encapsulateKey(
        shares[i].value,
        {
          ml_kem: base64Decode(trustee.public_keys.ml_kem),
          kaz_kem: base64Decode(trustee.public_keys.kaz_kem)
        }
      );

      const signature = await combinedSign(
        {
          ml_dsa: keys.privateKeys.ml_dsa,
          kaz_sign: keys.privateKeys.kaz_sign
        },
        canonicalize({
          share_index: shares[i].index,
          trustee_id: trustee.id,
          wrapped_value: base64Encode(wrappedKey)
        })
      );

      return {
        trustee_id: trustee.id,
        share_index: shares[i].index,
        encrypted_share: {
          wrapped_value: base64Encode(wrappedKey),
          kem_ciphertexts: kemCiphertexts
        },
        signature
      };
    })
  );

  // Clear shares from memory
  shares.forEach(s => s.value.fill(0));

  // Submit new shares
  await fetch('/api/v1/recovery/shares/setup', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      threshold,
      shares: shareBundle
    })
  });
}
```

## 7. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_RECOVERY_NOT_SETUP` | No recovery shares exist | Cannot recover |
| `E_REQUEST_NOT_FOUND` | Invalid recovery request | Restart process |
| `E_REQUEST_EXPIRED` | Recovery request timed out | Restart process |
| `E_THRESHOLD_NOT_REACHED` | Not enough approvals | Wait for more trustees |
| `E_VERIFICATION_FAILED` | Identity not verified | Contact admin |
| `E_ALREADY_APPROVED` | Trustee already approved | N/A |
| `E_NOT_TRUSTEE` | User is not a trustee | N/A |
| `E_SHARE_INDEX_MISMATCH` | Wrong share submitted | Verify share index |

## 8. Security Considerations

### 8.1 Threshold Security

- Require k=3 of n=5 for reconstruction
- Single trustee cannot recover alone
- Collusion of k-1 trustees reveals nothing

### 8.2 Identity Verification

- Multi-factor verification required
- Admin approval for sensitive accounts
- Video call option for high-security

### 8.3 Share Re-encryption

- Trustees decrypt with their keys
- Re-encrypt for user's NEW keys
- Original share never transmitted in plaintext

### 8.4 Post-Recovery

- Old credentials immediately revoked
- Recovery shares must be regenerated
- Audit trail maintained

## 9. Recovery Request Expiration

```typescript
// Recovery requests expire after 72 hours by default
const RECOVERY_REQUEST_EXPIRY = 72 * 60 * 60 * 1000; // 72 hours

// Trustees should be notified periodically
const REMINDER_INTERVALS = [
  24 * 60 * 60 * 1000,  // 24 hours
  48 * 60 * 60 * 1000,  // 48 hours
  66 * 60 * 60 * 1000   // 66 hours (6 hours before expiry)
];
```

## 10. Cancel Recovery Request

```typescript
async function cancelRecoveryRequest(
  requestId: string,
  token: string  // Temp token or admin token
): Promise<void> {

  const response = await fetch(`/api/v1/recovery/requests/${requestId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new RecoveryError(error.error.code, error.error.message);
  }
}
```
