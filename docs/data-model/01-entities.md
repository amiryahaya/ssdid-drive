# Entity Definitions

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document defines the core entities in SecureSharing. Each entity is described with its purpose, relationships, and attributes.

## 2. Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           ENTITY RELATIONSHIPS                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────┐                              ┌─────────────┐                   │
│  │   TENANT    │──────────────────────────────│    USER     │                   │
│  │             │ 1                          * │             │                   │
│  └──────┬──────┘                              └──────┬──────┘                   │
│         │                                           │                           │
│         │ 1                                   ┌─────┼─────┬─────────┐           │
│         │                                     │     │     │         │           │
│         │ *                                   │ 1   │ 1   │ 1       │ 1         │
│  ┌──────┴──────┐                              │     │     │         │           │
│  │  IDP_CONFIG │◄────────────┐                │ *   │ *   │ *       │ *         │
│  └─────────────┘             │         ┌──────┴───┐ │ ┌───┴────┐ ┌──┴─────────┐ │
│                              │         │CREDENTIAL│ │ │RECOVERY│ │ SHARE_LINK │ │
│                              └─────────│          │ │ │ SHARE  │ │            │ │
│                                        └──────────┘ │ └────────┘ └────────────┘ │
│                                                     │                           │
│                                              ┌──────┴──────┐                    │
│                                              │   FOLDER    │◄────────┐          │
│                                              └──────┬──────┘         │          │
│                                                     │                │ parent   │
│                                              1      │ *              │          │
│                                                     │                │          │
│                                              ┌──────┴──────┐         │          │
│                                              │    FILE     │─────────┘          │
│                                              └──────┬──────┘                    │
│                                                     │                           │
│                                                     │ *                         │
│  ┌─────────────┐                              ┌─────┴───────┐                   │
│  │  RECOVERY   │                              │ SHARE_GRANT │                   │
│  │  REQUEST    │                              └──────┬──────┘                   │
│  └──────┬──────┘                                     │                          │
│         │                                            │ *                        │
│         │ *                                   ┌──────┴──────┐                   │
│  ┌──────┴──────┐                              │   AUDIT     │                   │
│  │  RECOVERY   │                              │   EVENT     │                   │
│  │  APPROVAL   │                              └─────────────┘                   │
│  └─────────────┘                                                                │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Key Relationships**:
- **User → Credential**: One user can have multiple authentication credentials (passkeys, OIDC)
- **User → ShareLink**: User creates share links for anonymous/external sharing
- **User → ShareGrant**: User-to-user sharing with cryptographic keys
- **Credential → IdpConfig**: OIDC credentials link to their provider configuration

### Master Key Storage Model (Credential-Authoritative)

Each credential type owns its MK storage. There is no "canonical" copy. Storage location depends on whether the IdP provides unique key material (configured via `IdpConfig.provides_key_material`).

**Storage by Credential Type:**

| Credential Type | `provides_key_material` | MK Storage Location | Encryption Key |
|-----------------|-------------------------|---------------------|----------------|
| WebAuthn (Passkey) | `true` (always) | `Credential.encrypted_master_key` | Passkey's unique PRF output |
| OIDC | `false` (always) | `User.vault_encrypted_master_key` | Vault password + salt |
| SAML | `false` (always) | `User.vault_encrypted_master_key` | Vault password + salt |
| Digital ID (cert-based) | `true` (configured) | `Credential.encrypted_master_key` | Derived from certificate/private key |
| Digital ID (OIDC-based) | `false` (configured) | `User.vault_encrypted_master_key` | Vault password + salt |

```
┌─────────────────────────────────────────────────────────────────┐
│              MK STORAGE ARCHITECTURE (Credential-Authoritative)  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  USER                                                           │
│  ├── vault_encrypted_master_key ◄─── For credentials WITHOUT    │
│  ├── vault_mk_nonce                   key material (OIDC/SAML/  │
│  ├── vault_salt                       some Digital ID)          │
│  │                                    NULL if all credentials   │
│  │                                    provide key material      │
│  │                                                              │
│  └── CREDENTIALS[]                                              │
│       ├── Credential 1 (WebAuthn - passkey A)                   │
│       │   ├── encrypted_master_key ◄─── MK encrypted by PRF_A   │
│       │   └── mk_nonce                  (provides_key_material) │
│       │                                                         │
│       ├── Credential 2 (Digital ID - cert-based)                │
│       │   ├── encrypted_master_key ◄─── MK encrypted by cert key│
│       │   └── mk_nonce                  (provides_key_material) │
│       │                                                         │
│       ├── Credential 3 (OIDC)                                   │
│       │   ├── encrypted_master_key = NULL                       │
│       │   └── mk_nonce = NULL           (!provides_key_material)│
│       │       (Uses User.vault_encrypted_master_key)            │
│       │                                                         │
│       └── Credential 4 (Digital ID - OIDC-based)                │
│           ├── encrypted_master_key = NULL                       │
│           └── mk_nonce = NULL           (!provides_key_material)│
│               (Uses User.vault_encrypted_master_key)            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**MK Resolution Rules** (MUST be followed during authentication):

| `IdpConfig.provides_key_material` | MK Source |
|-----------------------------------|-----------|
| `true` | `Credential.encrypted_master_key` |
| `false` | `User.vault_encrypted_master_key` |

#### Login Precedence Rules (Multi-Credential)

When a user has multiple credentials, the MK source is determined by **the credential being used to authenticate**, not by any global user preference. The algorithm is:

```
FUNCTION resolve_mk_source(credential, user):
    idp_config = get_idp_config(credential.idp_config_id)

    IF idp_config.provides_key_material == TRUE:
        # Credential owns its MK copy
        IF credential.encrypted_master_key IS NULL:
            RAISE ERROR "E_MK_NOT_FOUND: Credential missing encrypted_master_key"
        RETURN {
            source: "credential",
            encrypted_mk: credential.encrypted_master_key,
            nonce: credential.mk_nonce,
            key_derivation: "idp_key_material"  # PRF, certificate, etc.
        }
    ELSE:
        # Credential uses vault (shared across non-key-material credentials)
        IF user.vault_encrypted_master_key IS NULL:
            RAISE ERROR "E_VAULT_NOT_CONFIGURED: Vault password required but not set up"
        RETURN {
            source: "vault",
            encrypted_mk: user.vault_encrypted_master_key,
            nonce: user.vault_mk_nonce,
            salt: user.vault_salt,
            key_derivation: "vault_password"
        }
```

**Example Scenarios:**

| Scenario | Authenticating With | MK Source |
|----------|---------------------|-----------|
| User has WebAuthn + OIDC credentials | WebAuthn passkey | `Credential.encrypted_master_key` (of that passkey) |
| User has WebAuthn + OIDC credentials | OIDC | `User.vault_encrypted_master_key` |
| User has 2 WebAuthn passkeys | Passkey A | `Credential.encrypted_master_key` (of Passkey A) |
| User has 2 WebAuthn passkeys | Passkey B | `Credential.encrypted_master_key` (of Passkey B) |
| User has OIDC + SAML credentials | OIDC | `User.vault_encrypted_master_key` (shared) |
| User has OIDC + SAML credentials | SAML | `User.vault_encrypted_master_key` (shared) |

**Validation Rules:**

1. **Credential with `provides_key_material=true`**: MUST have non-NULL `encrypted_master_key` and `mk_nonce`
2. **User with any `provides_key_material=false` credential**: MUST have non-NULL `vault_encrypted_master_key`, `vault_mk_nonce`, and `vault_salt`
3. **Never mix sources**: During a single login, use exactly one MK source based on the authenticating credential

**Error Conditions:**

| Condition | Error Code | Resolution |
|-----------|------------|------------|
| WebAuthn credential has NULL `encrypted_master_key` | `E_MK_NOT_FOUND` | Re-register credential or recover MK |
| OIDC login but `vault_encrypted_master_key` is NULL | `E_VAULT_NOT_CONFIGURED` | User must set up vault password first |
| Credential's IdpConfig not found | `E_IDP_CONFIG_NOT_FOUND` | Database integrity issue |

**Why This Design?**

- **IdPs with key material** (WebAuthn, cert-based Digital ID): Each credential has unique key material, so MK must be encrypted separately per credential. Stored in `Credential.encrypted_master_key`.

- **IdPs without key material** (OIDC, SAML, OIDC-based Digital ID): No unique key material from IdP. Users provide a vault password, which combined with `User.vault_salt` derives the key. All such credentials share the vault copy.

**Registration Flow (IdP with key material: WebAuthn, cert-based Digital ID)**:
1. Client generates MK
2. Client derives encryption key from IdP's key material:
   - WebAuthn: PRF output from passkey
   - Digital ID: Derived from certificate private key
3. Client encrypts MK with derived key
4. Stores in `Credential.encrypted_master_key`
5. `User.vault_*` fields remain NULL (no vault password needed)

**Registration Flow (IdP without key material: OIDC, SAML, OIDC-based Digital ID)**:
1. Client generates MK
2. User provides vault password
3. Client derives key: `HKDF(Argon2id(vault_password, vault_salt), "master-key")`
4. Client encrypts MK with derived key
5. Stores in `User.vault_encrypted_master_key`
6. `Credential.encrypted_master_key` remains NULL

**Adding Credential with Key Material** (to existing user):
1. User authenticates with existing credential → obtains MK in memory
2. User registers new credential (passkey or cert-based Digital ID)
3. Client derives key from new credential's key material
4. Client encrypts MK with derived key
5. Stores in new `Credential.encrypted_master_key`

**Adding Credential without Key Material** (to user with only key-material credentials):
1. User authenticates with existing credential → obtains MK in memory
2. User sets up vault password (one-time, if not already set)
3. Client generates `vault_salt`, derives key from vault password
4. Client encrypts MK with vault-derived key
5. Stores in `User.vault_encrypted_master_key`
6. New credential created with `encrypted_master_key = NULL`

**Critical Invariant**: All encrypted MK copies (credential-level and vault-level) decrypt to the **same** MK. They are copies encrypted with different keys, not different master keys.

#### Credential Lifecycle & MK Migration

This section defines how MK storage is affected by credential additions, removals, and configuration changes.

**Credential Removal Rules:**

```
FUNCTION remove_credential(credential_id, user):
    credential = get_credential(credential_id)
    remaining_credentials = get_user_credentials(user.id).exclude(credential_id)

    # RULE 1: User must retain at least one credential
    IF remaining_credentials.count() == 0:
        RAISE ERROR "E_LAST_CREDENTIAL: Cannot remove last credential"

    # RULE 2: Delete the credential (cascades encrypted_master_key)
    DELETE credential

    # RULE 3: Clean up vault if no longer needed
    idp_config = get_idp_config(credential.idp_config_id)
    IF idp_config.provides_key_material == FALSE:
        # Check if any remaining credentials use the vault
        vault_credentials = remaining_credentials.filter(
            c => get_idp_config(c.idp_config_id).provides_key_material == FALSE
        )
        IF vault_credentials.count() == 0:
            # No credentials use vault anymore - clear it
            user.vault_encrypted_master_key = NULL
            user.vault_mk_nonce = NULL
            user.vault_salt = NULL
            SAVE user

    RETURN success
```

**Credential Removal Scenarios:**

| Current Credentials | Removing | Result |
|---------------------|----------|--------|
| 1 Passkey | Passkey | ❌ ERROR: Cannot remove last credential |
| 2 Passkeys | Passkey A | ✅ Delete Passkey A's `encrypted_master_key` |
| Passkey + OIDC | Passkey | ✅ Delete Passkey's MK; vault remains |
| Passkey + OIDC | OIDC | ✅ Delete OIDC credential; clear `vault_*` fields |
| OIDC + SAML | OIDC | ✅ Delete OIDC credential; vault remains (SAML uses it) |
| OIDC + SAML | SAML | ✅ Delete SAML credential; vault remains (OIDC uses it) |

**Vault Password Change:**

When a user changes their vault password, only the vault-stored MK copy is re-encrypted. Credential-level MK copies are unaffected.

```
FUNCTION change_vault_password(user, current_password, new_password):
    # Step 1: Verify current password
    current_key = HKDF(Argon2id(current_password, user.vault_salt), "master-key")
    mk = AES-GCM-Decrypt(current_key, user.vault_mk_nonce, user.vault_encrypted_master_key)

    IF decryption_failed:
        RAISE ERROR "E_INVALID_PASSWORD: Current password incorrect"

    # Step 2: Generate new salt and derive new key
    new_salt = SecureRandom(32)
    new_key = HKDF(Argon2id(new_password, new_salt), "master-key")
    new_nonce = SecureRandom(12)

    # Step 3: Re-encrypt MK with new key
    new_encrypted_mk = AES-GCM-Encrypt(new_key, new_nonce, mk)

    # Step 4: Atomic update
    user.vault_salt = new_salt
    user.vault_mk_nonce = new_nonce
    user.vault_encrypted_master_key = new_encrypted_mk
    SAVE user

    # Step 5: Secure cleanup
    SecureWipe(mk)
    SecureWipe(current_key)
    SecureWipe(new_key)

    RETURN success
```

**Session Impact**: Active sessions retain MK in memory. Password change does not invalidate existing sessions. To force re-authentication, use separate session revocation.

**IdP Configuration Changes:**

The `provides_key_material` flag on `IdpConfig` determines MK storage location. Changing this flag after credentials exist creates migration complexity.

| Change | Impact | Recommendation |
|--------|--------|----------------|
| `false` → `true` | Existing credentials have NULL `encrypted_master_key` | ❌ NOT SUPPORTED |
| `true` → `false` | Existing credentials have orphaned `encrypted_master_key` | ❌ NOT SUPPORTED |

**Rule**: `IdpConfig.provides_key_material` is **immutable after the first credential is created** for that IdP configuration.

```sql
-- Enforcement via trigger (optional)
CREATE OR REPLACE FUNCTION prevent_provides_key_material_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.provides_key_material != NEW.provides_key_material THEN
        IF EXISTS (SELECT 1 FROM credentials WHERE idp_config_id = OLD.id) THEN
            RAISE EXCEPTION 'Cannot change provides_key_material after credentials exist';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_idp_config_immutable_key_material
    BEFORE UPDATE ON idp_configs
    FOR EACH ROW
    EXECUTE FUNCTION prevent_provides_key_material_change();
```

**MK Synchronization (Multi-Credential):**

All MK copies must remain synchronized. When MK is rotated (e.g., during recovery), ALL copies must be updated:

```
FUNCTION rotate_master_key(user, new_mk):
    # Re-encrypt for each credential with key material
    FOR credential IN get_credentials_with_key_material(user.id):
        idp_key = derive_key_from_credential(credential)
        new_nonce = SecureRandom(12)
        credential.encrypted_master_key = AES-GCM-Encrypt(idp_key, new_nonce, new_mk)
        credential.mk_nonce = new_nonce
        SAVE credential

    # Re-encrypt vault if any credentials use it
    IF has_vault_credentials(user.id):
        # User must provide vault password for re-encryption
        RAISE PROMPT "E_VAULT_PASSWORD_REQUIRED: Enter vault password to complete MK rotation"
        vault_key = HKDF(Argon2id(vault_password, user.vault_salt), "master-key")
        new_nonce = SecureRandom(12)
        user.vault_encrypted_master_key = AES-GCM-Encrypt(vault_key, new_nonce, new_mk)
        user.vault_mk_nonce = new_nonce
        SAVE user

    # Re-encrypt all PQC private keys with new MK
    re_encrypt_private_keys(user, new_mk)

    RETURN success
```

**Recovery Implications**: During Shamir recovery, the reconstructed MK must be re-encrypted for ALL credential storage locations. See [Recovery Flow](../flows/08-recovery-flow.md) for details.

## 3. Core Entities

### 3.1 Tenant

**Purpose**: Represents an organization using the platform. Provides multi-tenant isolation.

```yaml
Tenant:
  description: "Organization or workspace"
  constraints:
    - Cryptographic isolation between tenants
    - Users cannot share across tenant boundaries

  attributes:
    id:
      type: UUID
      description: "Unique identifier"
      generated: true

    name:
      type: String
      max_length: 256
      description: "Organization display name"
      example: "Acme Corporation"

    slug:
      type: String
      max_length: 64
      pattern: "^[a-z0-9-]+$"
      unique: true
      description: "URL-safe identifier for subdomain"
      example: "acme-corp"

    status:
      type: Enum
      values: [active, suspended, deleted]
      default: active

    plan:
      type: Enum
      values: [free, pro, enterprise]
      default: free

    storage_quota_bytes:
      type: BigInt
      default: 10737418240  # 10 GiB
      description: "Total storage limit for tenant"

    max_users:
      type: Integer
      default: 10
      description: "Maximum users allowed"

    settings:
      type: JSON
      description: "Tenant-specific configuration"
      schema:
        default_recovery_threshold: Integer
        default_recovery_shares: Integer
        require_mfa: Boolean
        allowed_idp_types: String[]

    billing_email:
      type: String
      format: email
      nullable: true

    stripe_customer_id:
      type: String
      nullable: true

    created_at:
      type: Timestamp
      generated: true

    updated_at:
      type: Timestamp
      auto_update: true

  relationships:
    users:
      type: HasMany
      entity: User
      foreign_key: tenant_id

    idp_configs:
      type: HasMany
      entity: IdpConfig
      foreign_key: tenant_id
```

### 3.2 User

**Purpose**: Represents an individual user with cryptographic key material.

```yaml
User:
  description: "Individual user account"
  constraints:
    - Each user belongs to exactly one tenant
    - User owns cryptographic keys for zero-knowledge

  attributes:
    id:
      type: UUID
      generated: true

    tenant_id:
      type: UUID
      foreign_key: Tenant.id
      indexed: true

    external_id:
      type: String
      max_length: 256
      description: "ID from identity provider"
      nullable: true

    email:
      type: String
      format: email
      description: "User email (from IdP)"

    display_name:
      type: String
      max_length: 256
      nullable: true

    status:
      type: Enum
      values: [active, suspended, deleted]
      default: active

    role:
      type: Enum
      values: [member, admin, owner]
      default: member
      description: "Role within tenant"

    # Cryptographic material (all encrypted)
    # See "Master Key Storage Model (Credential-Authoritative)" section above.

    # Vault-based MK storage (for OIDC/SAML/Digital ID credentials)
    vault_encrypted_master_key:
      type: Bytes
      nullable: true
      description: |
        MK encrypted with vault password-derived key. Used by OIDC/SAML/Digital ID
        credentials (which don't provide unique key material like WebAuthn PRF).
        NULL if user only has WebAuthn credentials (no vault password set up).
        All encrypted MK copies decrypt to the SAME MK.

    vault_mk_nonce:
      type: Bytes
      length: 12
      nullable: true
      description: "Nonce for vault_encrypted_master_key (AES-256-GCM)"

    vault_salt:
      type: Bytes
      length: 32
      nullable: true
      description: |
        Salt for Argon2id(vault_password). Used to derive key for decrypting
        vault_encrypted_master_key. NULL if user has no vault password.

    public_keys:
      type: JSON
      description: "Public keys (not encrypted)"
      schema:
        ml_kem: Bytes      # 1,184 bytes
        ml_dsa: Bytes      # 1,952 bytes
        kaz_kem: Bytes
        kaz_sign: Bytes

    encrypted_private_keys:
      type: JSON
      description: "Private keys encrypted by MK"
      schema:
        ml_kem: { ciphertext: Bytes, nonce: Bytes }
        ml_dsa: { ciphertext: Bytes, nonce: Bytes }
        kaz_kem: { ciphertext: Bytes, nonce: Bytes }
        kaz_sign: { ciphertext: Bytes, nonce: Bytes }

    # Recovery
    recovery_setup_complete:
      type: Boolean
      default: false

    # Metadata
    last_login_at:
      type: Timestamp
      nullable: true

    created_at:
      type: Timestamp
      generated: true

    updated_at:
      type: Timestamp
      auto_update: true

  relationships:
    tenant:
      type: BelongsTo
      entity: Tenant

    root_folder:
      type: HasOne
      entity: Folder
      condition: "parent_id IS NULL"

    folders:
      type: HasMany
      entity: Folder
      foreign_key: owner_id

    files:
      type: HasMany
      entity: File
      foreign_key: owner_id

    shares_granted:
      type: HasMany
      entity: ShareGrant
      foreign_key: grantor_id

    shares_received:
      type: HasMany
      entity: ShareGrant
      foreign_key: grantee_id

    recovery_shares:
      type: HasMany
      entity: RecoveryShare
      foreign_key: user_id

    credentials:
      type: HasMany
      entity: Credential
      foreign_key: user_id
      description: "User's authentication credentials (passkeys, OIDC)"

    share_links:
      type: HasMany
      entity: ShareLink
      foreign_key: creator_id
      description: "Share links created by this user"

  indexes:
    - [tenant_id, email]
    - [tenant_id, status]
```

### 3.3 Folder

**Purpose**: Hierarchical container for files with its own KEK.

```yaml
Folder:
  description: "Directory/folder in user's vault"
  constraints:
    - Hierarchical (tree structure)
    - Each folder has exactly one KEK
    - Root folder has no parent

  attributes:
    id:
      type: UUID
      generated: true

    owner_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    parent_id:
      type: UUID
      foreign_key: Folder.id
      nullable: true  # null for root folder
      indexed: true

    # Encrypted data (server cannot read)
    encrypted_metadata:
      type: Bytes
      description: "Encrypted JSON with name, color, icon, etc."

    metadata_nonce:
      type: Bytes
      length: 12

    # KEK management
    owner_key_access:
      type: JSON
      description: "KEK encapsulated for owner"
      schema:
        wrapped_kek: Bytes
        kem_ciphertexts:
          - algorithm: String
            ciphertext: Bytes

    wrapped_kek:
      type: Bytes
      description: "KEK wrapped by parent's KEK (null for root)"
      nullable: true

    # Cryptographic integrity
    signature:
      type: JSON
      description: "Owner's signature over folder creation"
      reference: "crypto/05-signature-protocol.md Section 4.4"
      schema:
        ml_dsa: Bytes    # ML-DSA-65 signature
        kaz_sign: Bytes  # KAZ-SIGN-256 signature

    # Metadata
    is_root:
      type: Boolean
      default: false
      description: "True if this is user's root folder"

    item_count:
      type: Integer
      default: 0
      description: "Cached count of direct children"

    created_at:
      type: Timestamp
      generated: true

    updated_at:
      type: Timestamp
      auto_update: true

  relationships:
    owner:
      type: BelongsTo
      entity: User

    parent:
      type: BelongsTo
      entity: Folder
      nullable: true

    children:
      type: HasMany
      entity: Folder
      foreign_key: parent_id

    files:
      type: HasMany
      entity: File
      foreign_key: folder_id

    share_grants:
      type: HasMany
      entity: ShareGrant
      condition: "resource_type = 'folder'"

  indexes:
    - [owner_id, parent_id]
    - [owner_id, is_root]
```

### 3.4 File

**Purpose**: Encrypted file with its own DEK.

**Encryption Format**: See [docs/crypto/03-encryption-protocol.md](../crypto/03-encryption-protocol.md) for the canonical file encryption specification.

**Storage Separation**:
- **Blob** (object storage): Encrypted file content with fixed 64-byte header + encrypted chunks
- **Database**: Metadata, wrapped DEK, and signature (fields below)

```yaml
File:
  description: "Encrypted file in user's vault"
  constraints:
    - Each file has exactly one DEK
    - File belongs to exactly one folder
    - Blob contains only encrypted content (no metadata/signature)
    - Metadata and signature stored in database for zero-knowledge operations

  attributes:
    id:
      type: UUID
      generated: true

    owner_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    folder_id:
      type: UUID
      foreign_key: Folder.id
      indexed: true

    # Encrypted data
    encrypted_metadata:
      type: Bytes
      description: "Encrypted filename, size, mime type, etc."

    metadata_nonce:
      type: Bytes
      length: 12

    # DEK management
    wrapped_dek:
      type: Bytes
      description: "DEK wrapped by folder's KEK"

    # Blob storage
    blob_storage_key:
      type: String
      max_length: 512
      description: "Path/key in object storage"

    blob_size:
      type: BigInt
      description: "Size of encrypted blob in bytes"

    blob_hash:
      type: String
      length: 64
      description: "SHA-256 of encrypted blob (hex)"

    # Signature
    signature:
      type: JSON
      description: "Owner's combined signature"
      schema:
        ml_dsa: Bytes
        kaz_sign: Bytes

    # Version tracking
    version:
      type: Integer
      default: 1

    # Soft delete
    deleted_at:
      type: Timestamp
      nullable: true
      description: "When file was soft-deleted (null = active)"

    permanent_deletion_at:
      type: Timestamp
      nullable: true
      description: "When file will be permanently deleted (30 days after deleted_at)"

    # Metadata
    created_at:
      type: Timestamp
      generated: true

    updated_at:
      type: Timestamp
      auto_update: true

  relationships:
    owner:
      type: BelongsTo
      entity: User

    folder:
      type: BelongsTo
      entity: Folder

    share_grants:
      type: HasMany
      entity: ShareGrant
      condition: "resource_type = 'file'"

  indexes:
    - [folder_id, created_at]
    - [owner_id, updated_at]
    - [owner_id, deleted_at]  # For trash listing
    - [blob_hash]  # For deduplication
    - [permanent_deletion_at]  # For cleanup job
```

### 3.5 ShareGrant

**Purpose**: Cryptographic share of file or folder access.

```yaml
ShareGrant:
  description: "Permission grant from one user to another"
  constraints:
    - Contains encapsulated key material
    - Signed by grantor
    - Deletable for revocation

  attributes:
    id:
      type: UUID
      generated: true

    # Resource identification
    resource_type:
      type: Enum
      values: [file, folder]

    resource_id:
      type: UUID
      description: "File or Folder ID"
      indexed: true

    # Parties
    grantor_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    grantee_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    # Cryptographic material
    wrapped_key:
      type: Bytes
      description: "DEK (file) or KEK (folder) encrypted for grantee"

    kem_ciphertexts:
      type: JSON
      schema:
        - algorithm: String  # "ML-KEM-768" or "KAZ-KEM"
          ciphertext: Bytes

    # Access control
    permission:
      type: Enum
      values: [read, write, admin]
      default: read

    recursive:
      type: Boolean
      default: false
      description: "For folders: include all descendants"

    expiry:
      type: Timestamp
      nullable: true
      description: "Optional expiration time"

    # Integrity
    signature:
      type: JSON
      schema:
        ml_dsa: Bytes
        kaz_sign: Bytes

    # Metadata
    created_at:
      type: Timestamp
      generated: true

  relationships:
    grantor:
      type: BelongsTo
      entity: User

    grantee:
      type: BelongsTo
      entity: User

    file:
      type: BelongsTo
      entity: File
      condition: "resource_type = 'file'"

    folder:
      type: BelongsTo
      entity: Folder
      condition: "resource_type = 'folder'"

  indexes:
    - [grantee_id, resource_type]
    - [resource_type, resource_id]
    - [grantor_id, created_at]
```

### 3.6 IdpConfig

**Purpose**: Identity provider configuration per tenant.

```yaml
IdpConfig:
  description: "Identity provider configuration"

  attributes:
    id:
      type: UUID
      generated: true

    tenant_id:
      type: UUID
      foreign_key: Tenant.id
      indexed: true

    type:
      type: Enum
      values: [webauthn, digital_id, oidc, saml]

    name:
      type: String
      max_length: 128
      description: "Display name (e.g., 'Company SSO')"

    enabled:
      type: Boolean
      default: true

    priority:
      type: Integer
      default: 0
      description: "Display order (lower = higher priority)"

    # Key material capability
    provides_key_material:
      type: Boolean
      default: false
      description: |
        Whether this IdP provides unique key material for MK encryption.
        - true: Credentials can encrypt MK directly (like WebAuthn PRF).
                MK stored in Credential.encrypted_master_key.
        - false: No key material. User needs vault password.
                MK stored in User.vault_encrypted_master_key.

        Typical values by type:
        - webauthn: true (always, PRF provides key material)
        - oidc: false (tokens only, no key material)
        - saml: false (assertions only, no key material)
        - digital_id: CONFIGURABLE (depends on implementation)
          - Certificate-based with private key access: true
          - OIDC-based (e.g., SingPass): false

    config:
      type: JSON
      description: "Type-specific configuration"
      # Schema varies by type

    created_at:
      type: Timestamp
      generated: true

    updated_at:
      type: Timestamp
      auto_update: true

  relationships:
    tenant:
      type: BelongsTo
      entity: Tenant

  indexes:
    - [tenant_id, enabled, priority]
```

### 3.7 Credential

**Purpose**: Stores authentication credentials (WebAuthn passkeys, OIDC/SAML links, Digital ID) per user.

**UI Guideline**: Credential management UI should display `IdpConfig.name` (e.g., "Acme Corp SSO", "Google") rather than the protocol type (`oidc`, `saml`). Users don't need to know the underlying protocol.

```
┌─────────────────────────────────────────────┐
│  Your Sign-in Methods                       │
├─────────────────────────────────────────────┤
│  🔑 MacBook Pro Passkey          [Remove]   │  ← device_name
│  🔑 iPhone Passkey               [Remove]   │  ← device_name
│  🏢 Acme Corp SSO                [Remove]   │  ← IdpConfig.name (not "SAML")
│  🌐 Google                       [Remove]   │  ← IdpConfig.name (not "OIDC")
│  🪪 MyDigital ID                 [Remove]   │  ← IdpConfig.name
└─────────────────────────────────────────────┘
```

```yaml
Credential:
  description: "User authentication credential (passkey, OIDC, SAML, Digital ID)"
  constraints:
    - Users can have multiple credentials
    - Each credential may have its own encrypted MK (for IdPs with key material)

  attributes:
    id:
      type: UUID
      generated: true

    user_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    type:
      type: Enum
      values: [webauthn, digital_id, oidc, saml]

    # WebAuthn-specific fields
    credential_id:
      type: Bytes
      description: "WebAuthn credential ID (base64url in API)"
      nullable: true

    public_key:
      type: Bytes
      description: "WebAuthn public key (COSE format)"
      nullable: true

    counter:
      type: Integer
      default: 0
      description: "WebAuthn signature counter for replay protection"

    transports:
      type: JSON
      nullable: true
      description: "WebAuthn transports (usb, nfc, ble, internal)"
      example: ["internal", "hybrid"]

    # OIDC/Digital ID specific
    external_id:
      type: String
      max_length: 256
      nullable: true
      description: "Subject ID from OIDC/Digital ID provider"

    provider_id:
      type: UUID
      foreign_key: IdpConfig.id
      nullable: true
      description: "Which IdP config this credential uses"

    # Credential-level MK storage (for IdPs with key material)
    # See "Master Key Storage Model (Credential-Authoritative)" section.
    encrypted_master_key:
      type: Bytes
      nullable: true
      description: |
        MK encrypted with THIS credential's unique key material.
        Populated based on IdpConfig.provides_key_material:
        - WebAuthn: ALWAYS populated. Encrypted by passkey's PRF output.
        - Digital ID (cert-based, provides_key_material=true): Populated.
          Encrypted by key derived from certificate.
        - Digital ID (OIDC-based, provides_key_material=false): NULL.
          Uses User.vault_encrypted_master_key.
        - OIDC/SAML: ALWAYS NULL. Uses User.vault_encrypted_master_key.
        CRITICAL: Decrypts to the SAME MK as all other encrypted MK copies.

    mk_nonce:
      type: Bytes
      length: 12
      nullable: true
      description: |
        Nonce for encrypted_master_key (AES-256-GCM).
        NULL when encrypted_master_key is NULL.

    # Metadata
    device_name:
      type: String
      max_length: 128
      nullable: true
      description: "User-friendly name (e.g., 'MacBook Pro')"

    last_used_at:
      type: Timestamp
      nullable: true

    created_at:
      type: Timestamp
      generated: true

  relationships:
    user:
      type: BelongsTo
      entity: User

    idp_config:
      type: BelongsTo
      entity: IdpConfig
      nullable: true

  indexes:
    - [user_id, type]
    - [credential_id]  # For WebAuthn lookup
    - [external_id]    # For OIDC lookup
```

### 3.8 ShareLink

**Purpose**: Anonymous URL-based sharing for external recipients.

```yaml
ShareLink:
  description: "Shareable link for anonymous access"
  constraints:
    - Does not require recipient to have an account
    - Key is wrapped with password-derived key (if protected)
    - Download count enforced server-side

  attributes:
    id:
      type: UUID
      generated: true

    # Resource
    resource_type:
      type: Enum
      values: [file, folder]

    resource_id:
      type: UUID
      indexed: true

    # Creator
    creator_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    # Access token (in URL)
    token:
      type: String
      length: 32
      unique: true
      description: "Random token for URL (e.g., 'abc123xyz')"

    # Cryptographic material
    wrapped_key:
      type: Bytes
      description: "DEK/KEK wrapped with password-derived key or raw"

    # Password protection
    password_protected:
      type: Boolean
      default: false

    password_salt:
      type: Bytes
      nullable: true
      description: "Salt for Argon2id password derivation"

    password_hash:
      type: Bytes
      nullable: true
      description: "Hash to verify password before revealing wrapped_key"

    # Access control
    permission:
      type: Enum
      values: [read, write]
      default: read

    expiry:
      type: Timestamp
      nullable: true

    max_downloads:
      type: Integer
      nullable: true
      description: "Maximum download count (null = unlimited)"

    download_count:
      type: Integer
      default: 0

    # Integrity
    signature:
      type: JSON
      schema:
        ml_dsa: Bytes
        kaz_sign: Bytes

    # Metadata
    created_at:
      type: Timestamp
      generated: true

  relationships:
    creator:
      type: BelongsTo
      entity: User

    file:
      type: BelongsTo
      entity: File
      condition: "resource_type = 'file'"

    folder:
      type: BelongsTo
      entity: Folder
      condition: "resource_type = 'folder'"

  indexes:
    - [token]  # Primary lookup
    - [creator_id, created_at]
    - [resource_type, resource_id]
    - [expiry]  # For cleanup
```

### 3.9 RecoveryShare

**Purpose**: Shamir share for master key recovery.

```yaml
RecoveryShare:
  description: "Shamir share held by trustee"

  attributes:
    id:
      type: UUID
      generated: true

    user_id:
      type: UUID
      foreign_key: User.id
      indexed: true
      description: "User whose MK is split"

    trustee_id:
      type: UUID
      foreign_key: User.id
      indexed: true
      description: "User holding this share"

    share_index:
      type: Integer
      description: "1-based share index"

    # Encrypted share (only trustee can decrypt)
    encrypted_share:
      type: JSON
      schema:
        wrapped_value: Bytes
        kem_ciphertexts:
          - algorithm: String
            ciphertext: Bytes

    # Signatures
    user_signature:
      type: JSON
      schema:
        ml_dsa: Bytes
        kaz_sign: Bytes

    trustee_acknowledgment:
      type: JSON
      nullable: true
      schema:
        ml_dsa: Bytes
        kaz_sign: Bytes

    # Status
    acknowledged_at:
      type: Timestamp
      nullable: true

    created_at:
      type: Timestamp
      generated: true

  relationships:
    user:
      type: BelongsTo
      entity: User

    trustee:
      type: BelongsTo
      entity: User

  indexes:
    - [user_id, share_index]
    - [trustee_id, acknowledged_at]
```

### 3.10 RecoveryRequest

**Purpose**: Tracks key recovery requests.

```yaml
RecoveryRequest:
  description: "Master key recovery request"

  attributes:
    id:
      type: UUID
      generated: true

    user_id:
      type: UUID
      foreign_key: User.id
      indexed: true

    status:
      type: Enum
      values: [pending, approved, completed, expired, cancelled]
      default: pending

    reason:
      type: Enum
      values: [device_lost, passkey_unavailable, credential_reset, admin_request]

    verification_method:
      type: String
      description: "How identity was verified"

    # New keys (for re-encryption of shares AND signature verification)
    # Includes BOTH KEM keys (for re-encrypting shares) AND signing keys (for verifying approvals)
    new_public_keys:
      type: JSON
      schema:
        ml_kem: Bytes     # For re-encrypting shares
        ml_dsa: Bytes     # For verifying user's signatures
        kaz_kem: Bytes    # For re-encrypting shares
        kaz_sign: Bytes   # For verifying user's signatures

    # Progress tracking
    approvals_required:
      type: Integer
      description: "k from Shamir threshold"

    approvals_received:
      type: Integer
      default: 0

    # Timing
    expires_at:
      type: Timestamp

    completed_at:
      type: Timestamp
      nullable: true

    created_at:
      type: Timestamp
      generated: true

  relationships:
    user:
      type: BelongsTo
      entity: User

    approvals:
      type: HasMany
      entity: RecoveryApproval
      foreign_key: request_id

  indexes:
    - [user_id, status]
    - [status, expires_at]
```

### 3.11 AuditEvent

**Purpose**: Security and compliance audit logging.

```yaml
AuditEvent:
  description: "Audit log entry"
  constraints:
    - Immutable (append-only)
    - Retained per compliance requirements

  attributes:
    id:
      type: UUID
      generated: true

    tenant_id:
      type: UUID
      foreign_key: Tenant.id
      indexed: true

    user_id:
      type: UUID
      foreign_key: User.id
      nullable: true
      indexed: true

    event_type:
      type: String
      max_length: 64
      indexed: true
      examples:
        - "user.login"
        - "file.upload"
        - "file.download"
        - "share.create"
        - "share.revoke"
        - "recovery.request"
        - "recovery.approve"

    resource_type:
      type: String
      nullable: true

    resource_id:
      type: UUID
      nullable: true

    details:
      type: JSON
      description: "Event-specific data (no sensitive info)"

    ip_address:
      type: String
      max_length: 45  # IPv6

    user_agent:
      type: String
      max_length: 512
      nullable: true

    timestamp:
      type: Timestamp
      generated: true
      indexed: true

  indexes:
    - [tenant_id, timestamp]
    - [user_id, event_type, timestamp]
    - [resource_type, resource_id, timestamp]
```

## 4. Entity States

### 4.1 User Lifecycle

```
Created → Active → Suspended → Deleted
                 ↓
              Recovered
```

### 4.2 File Lifecycle

```
Uploading → Active → Soft Deleted → Permanently Deleted
              ↓           ↓
           Shared      Restored
                          ↓
                       Active
```

**Soft Delete**:
- `deleted_at` set to current timestamp
- `permanent_deletion_at` set to 30 days in future
- File excluded from folder contents but accessible via trash
- Can be restored before `permanent_deletion_at`

**Permanent Deletion**:
- Blob removed from object storage
- Database record removed
- Cannot be recovered

### 4.3 ShareGrant Lifecycle

```
Created → Active → Expired
             ↓
          Revoked
```

### 4.4 RecoveryRequest Lifecycle

```
Pending → Approved (threshold reached) → Completed
   ↓              ↓
Expired       Cancelled
```

## 5. Constraints Summary

| Constraint | Entities | Description |
|------------|----------|-------------|
| Tenant isolation | All | Users cannot access other tenants |
| Unique email per tenant | User | Email unique within tenant |
| Root folder per user | Folder | Each user has exactly one root |
| Acyclic folder hierarchy | Folder | No circular parent references |
| Single owner per resource | File, Folder | One owner, many shares |
| Signed share grants | ShareGrant | Signature required |
| Threshold recovery | RecoveryShare | k-of-n shares needed |

## 6. Enums and Types Reference

### 6.1 Permission vs AccessLevel

**Permission** (for ShareGrant):
```
values: [read, write, admin]
```
Used when creating or updating share grants. Defines what the grantee can do.

**AccessLevel** (API responses):
```
values: [read, write, admin, owner]
```
Used in API responses to indicate effective access level. Extends Permission with `owner`.

**IMPORTANT**: `owner` is NOT a share permission—it indicates the user owns the resource
(`owner_id == current_user_id`). You cannot grant "owner" permission via sharing.

### 6.2 Access Information in API Responses

When retrieving files or folders, the API includes an `access` object:

```yaml
access:
  source:
    type: Enum
    values: [owner, share]
    description: "How user has access to this resource"

  permission:
    type: Enum
    values: [owner, admin, write, read]
    description: "Effective permission level (AccessLevel, not Permission)"

  share_id:
    type: UUID
    nullable: true
    description: "If source is 'share', the ShareGrant ID"
```

### 6.3 Permission Hierarchy

| Level | Can Read | Can Write | Can Share | Can Delete | Notes |
|-------|----------|-----------|-----------|------------|-------|
| `read` | ✓ | - | - | - | View/download only |
| `write` | ✓ | ✓ | - | - | Can modify content |
| `admin` | ✓ | ✓ | ✓ | - | Can share with others |
| `owner` | ✓ | ✓ | ✓ | ✓ | Full control (not a share permission) |
