# TypeScript Interfaces

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document defines TypeScript interfaces for the SecureSharing client SDK. These types ensure type-safe interaction with encrypted data and cryptographic operations.

### Naming Conventions

All interface fields use **camelCase** naming convention:

| Field | Convention | Example |
|-------|------------|---------|
| MIME type | `mimeType` | `"application/pdf"` |
| Timestamps | `createdAt`, `modifiedAt` | ISO 8601 strings |
| Checksum | `checksum` | SHA-256 hex string |
| File name | `filename` | `"document.pdf"` |

> **Note**: Wire format (JSON over HTTP) uses the same camelCase convention. See [Wire Format](./04-wire-format.md) for API payload schemas.

## 2. Primitive Types

```typescript
/**
 * UUID string in standard format
 * @example "550e8400-e29b-41d4-a716-446655440000"
 */
type UUID = string;

/**
 * ISO 8601 timestamp string
 * @example "2025-01-15T10:30:00.000Z"
 */
type ISOTimestamp = string;

/**
 * Base64-encoded bytes
 */
type Base64Bytes = string;

/**
 * Hex-encoded bytes (lowercase)
 */
type HexBytes = string;
```

## 3. Cryptographic Types

### 3.1 Key Types

```typescript
/**
 * PQC algorithm identifiers
 */
type KEMAlgorithm = "ML-KEM-768" | "KAZ-KEM";
type SignatureAlgorithm = "ML-DSA-65" | "KAZ-SIGN";

/**
 * KEM key pair
 */
interface KEMKeyPair {
  algorithm: KEMAlgorithm;
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

/**
 * Signature key pair
 */
interface SignKeyPair {
  algorithm: SignatureAlgorithm;
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

/**
 * User's complete cryptographic key set
 */
interface UserKeySet {
  // KEM keys for receiving encrypted data
  kem: {
    mlKem: KEMKeyPair;
    kazKem: KEMKeyPair;
  };

  // Signature keys for signing
  sign: {
    mlDsa: SignKeyPair;
    kazSign: SignKeyPair;
  };
}

/**
 * Public keys only (for sharing with others)
 */
interface PublicKeySet {
  mlKem: Uint8Array;    // 1,184 bytes
  mlDsa: Uint8Array;    // 1,952 bytes
  kazKem: Uint8Array;
  kazSign: Uint8Array;
}
```

### 3.2 KEM Types

```typescript
/**
 * KEM ciphertext from encapsulation
 */
interface KEMCiphertext {
  algorithm: KEMAlgorithm;
  ciphertext: Uint8Array;
}

/**
 * Result of KEM encapsulation
 */
interface KEMEncapsulation {
  ciphertext: Uint8Array;
  sharedSecret: Uint8Array;
}

/**
 * Combined KEM result (dual algorithm)
 */
interface CombinedKEMResult {
  ciphertexts: KEMCiphertext[];
  combinedSharedSecret: Uint8Array;
}
```

### 3.3 Signature Types

```typescript
/**
 * Combined signature (both algorithms)
 */
interface CombinedSignature {
  mlDsa: Uint8Array;    // 3,309 bytes
  kazSign: Uint8Array;
}

/**
 * Serialized combined signature for storage/transmission
 */
interface SerializedSignature {
  ml_dsa: Base64Bytes;
  kaz_sign: Base64Bytes;
}
```

### 3.4 Encryption Types

```typescript
/**
 * AES-256-GCM encryption result
 */
interface AESEncryptionResult {
  ciphertext: Uint8Array;
  nonce: Uint8Array;      // 12 bytes
  tag: Uint8Array;        // 16 bytes
}

/**
 * Wrapped key (from AES-KWP)
 */
type WrappedKey = Uint8Array;

/**
 * Data Encryption Key
 */
type DEK = Uint8Array;  // 32 bytes

/**
 * Key Encryption Key
 */
type KEK = Uint8Array;  // 32 bytes

/**
 * Master Key
 */
type MasterKey = Uint8Array;  // 32 bytes
```

## 4. Entity Types

### 4.1 Tenant

```typescript
type TenantStatus = "active" | "suspended" | "deleted";
type TenantPlan = "free" | "pro" | "enterprise";

interface TenantSettings {
  defaultRecoveryThreshold: number;
  defaultRecoveryShares: number;
  requireMfa: boolean;
  allowedIdpTypes: IdpType[];
}

interface Tenant {
  id: UUID;
  name: string;
  slug: string;
  status: TenantStatus;
  plan: TenantPlan;
  storageQuotaBytes: number;
  maxUsers: number;
  settings: TenantSettings;
  billingEmail?: string;
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

/**
 * Tenant creation request
 */
interface CreateTenantRequest {
  name: string;
  slug: string;
  plan?: TenantPlan;
  settings?: Partial<TenantSettings>;
  billingEmail?: string;
}
```

### 4.2 User

```typescript
type UserStatus = "active" | "suspended" | "deleted";
type UserRole = "member" | "admin" | "owner";

interface User {
  id: UUID;
  tenantId: UUID;
  externalId?: string;
  email: string;
  displayName?: string;
  status: UserStatus;
  role: UserRole;
  recoverySetupComplete: boolean;
  lastLoginAt?: ISOTimestamp;
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

/**
 * User with public keys (for sharing)
 */
interface UserWithPublicKeys extends User {
  publicKeys: PublicKeySet;
}

/**
 * User search result (from /users/search endpoint)
 * Contains only KEM keys needed for key encapsulation during sharing
 */
interface UserSearchResult {
  id: UUID;
  email: string;
  displayName?: string;
  publicKeys: {
    ml_kem: Base64Bytes;
    kaz_kem: Base64Bytes;
  };
}

/**
 * User registration request
 *
 * MK storage depends on credential type (see Master Key Storage Model):
 * - WebAuthn/cert-based Digital ID: MK stored in credential (credentialEncryptedMk)
 * - OIDC/SAML/OIDC-based Digital ID: MK stored in user vault (vaultEncryptedMk)
 */
interface RegisterUserRequest {
  email: string;
  displayName?: string;
  publicKeys: SerializedPublicKeys;
  encryptedPrivateKeys: SerializedEncryptedPrivateKeys;

  // Credential info (required)
  credential: RegisterCredentialData;

  // Root folder (required) - client creates root folder during registration
  rootFolder: CreateRootFolderRequest;

  // Vault MK (for credentials WITHOUT key material: OIDC, SAML, some Digital ID)
  // Omit if credential provides key material (WebAuthn, cert-based Digital ID)
  vaultEncryptedMk?: Base64Bytes;
  vaultMkNonce?: Base64Bytes;
  vaultSalt?: Base64Bytes;
}

/**
 * Root folder creation request (during registration)
 * Root folder has no parent_id or wrapped_kek.
 */
interface CreateRootFolderRequest {
  encryptedMetadata: Base64Bytes;         // Encrypted folder name (e.g., "My Vault")
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;         // Root KEK encapsulated for owner
  createdAt: ISOTimestamp;
  signature: SerializedSignature;         // Owner's signature (see crypto/05-signature-protocol.md Section 4.4)
}

/**
 * Registration response
 */
interface RegisterUserResponse {
  user: {
    id: UUID;
    email: string;
    displayName: string;
    status: 'active' | 'pending';
  };
  rootFolder: {
    id: UUID;                             // Server-generated root folder ID
  };
  session: {
    token: string;
    expiresAt: ISOTimestamp;
  };
}

/**
 * Credential data for registration
 */
interface RegisterCredentialData {
  type: CredentialType;
  deviceName?: string;

  // WebAuthn specific
  credentialId?: Base64Bytes;
  publicKey?: Base64Bytes;
  transports?: string[];

  // OIDC/SAML/Digital ID specific
  externalId?: string;
  providerId?: UUID;

  // Credential-level MK (for credentials WITH key material: WebAuthn, cert-based Digital ID)
  // Omit if credential does not provide key material (OIDC, SAML, some Digital ID)
  encryptedMasterKey?: Base64Bytes;
  mkNonce?: Base64Bytes;
}

/**
 * MK Resolution Result
 *
 * Returned by resolveMkSource() to indicate where to find the encrypted MK
 * during login. The source is determined by the credential being used to authenticate:
 *
 * - If IdpConfig.providesKeyMaterial = true: Use credential's encryptedMasterKey
 * - If IdpConfig.providesKeyMaterial = false: Use user's vaultEncryptedMasterKey
 *
 * @see docs/data-model/01-entities.md "Login Precedence Rules (Multi-Credential)"
 */
type MkResolutionSource = "credential" | "vault";

interface MkResolutionResult {
  /** Where the encrypted MK is stored */
  source: MkResolutionSource;

  /** The encrypted master key bytes */
  encryptedMk: Base64Bytes;

  /** Nonce for AES-256-GCM decryption */
  nonce: Base64Bytes;

  /** Salt for vault password derivation (only present when source = "vault") */
  salt?: Base64Bytes;

  /** How to derive the decryption key */
  keyDerivation: "idp_key_material" | "vault_password";
}

/**
 * Resolve MK source for a login attempt
 *
 * IMPORTANT: The MK source is determined by the credential being used to authenticate,
 * NOT by any user preference. A user with multiple credentials may have different
 * MK copies encrypted with different keys.
 *
 * @param credential - The credential being used to authenticate
 * @param user - The user record (for vault fallback)
 * @param idpConfig - The IdP configuration for this credential
 * @returns MkResolutionResult indicating where to find the encrypted MK
 * @throws E_MK_NOT_FOUND if credential should have MK but doesn't
 * @throws E_VAULT_NOT_CONFIGURED if vault required but not set up
 */
type ResolveMkSourceFn = (
  credential: Credential,
  user: User,
  idpConfig: IdpConfig
) => MkResolutionResult;

interface SerializedPublicKeys {
  ml_kem: Base64Bytes;
  ml_dsa: Base64Bytes;
  kaz_kem: Base64Bytes;
  kaz_sign: Base64Bytes;
}

interface SerializedEncryptedPrivateKeys {
  ml_kem: { ciphertext: Base64Bytes; nonce: Base64Bytes };
  ml_dsa: { ciphertext: Base64Bytes; nonce: Base64Bytes };
  kaz_kem: { ciphertext: Base64Bytes; nonce: Base64Bytes };
  kaz_sign: { ciphertext: Base64Bytes; nonce: Base64Bytes };
}
```

### 4.3 Folder

```typescript
/**
 * Encrypted folder metadata (decrypted client-side)
 */
interface FolderMetadata {
  name: string;
  color?: string;
  icon?: string;
  description?: string;
}

/**
 * Owner key access (for KEK decapsulation)
 */
interface OwnerKeyAccess {
  wrappedKek: Base64Bytes;
  kemCiphertexts: SerializedKEMCiphertext[];
}

interface SerializedKEMCiphertext {
  algorithm: KEMAlgorithm;
  ciphertext: Base64Bytes;
}

/**
 * Folder as stored on server (encrypted)
 */
interface EncryptedFolder {
  id: UUID;
  ownerId: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;
  signature: SerializedSignature;        // Owner's signature (see crypto/05-signature-protocol.md Section 4.4)
  isRoot: boolean;
  itemCount: number;
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

/**
 * Folder with decrypted metadata (client-side)
 */
interface DecryptedFolder extends Omit<EncryptedFolder, "encryptedMetadata" | "metadataNonce"> {
  metadata: FolderMetadata;
}

/**
 * Create folder request
 */
interface CreateFolderRequest {
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;
  createdAt: ISOTimestamp;               // Client timestamp (included in signature)
  signature: SerializedSignature;        // Owner's signature (see crypto/05-signature-protocol.md Section 4.4)
}

/**
 * Update folder metadata request
 * Signature covers complete folder state after update.
 * See crypto/05-signature-protocol.md Section 4.4.1
 */
interface UpdateFolderRequest {
  encryptedMetadata: Base64Bytes;        // Updated encrypted metadata
  metadataNonce: Base64Bytes;            // New nonce (required for each update)
  updatedAt: ISOTimestamp;               // Client timestamp (included in signature)
  signature: SerializedSignature;        // Owner's signature over updated state
}

/**
 * Move folder request
 * Signature covers complete folder state after move.
 * See crypto/05-signature-protocol.md Section 4.4.2
 */
interface MoveFolderRequest {
  targetParentId: UUID;                  // New parent folder ID
  wrappedKek: Base64Bytes;               // KEK re-wrapped with new parent's KEK
  updatedAt: ISOTimestamp;               // Client timestamp (included in signature)
  signature: SerializedSignature;        // Owner's signature over moved state
}

/**
 * Folder response from API (includes owner public keys for signature verification)
 */
interface FolderResponse extends EncryptedFolder {
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;          // For signature verification
  };
  access: {
    source: 'owner' | 'share';
    permission: Permission | 'owner';
  };
}
```

### 4.4 File

```typescript
/**
 * Encrypted file metadata (decrypted client-side)
 */
interface FileMetadata {
  filename: string;
  mimeType: string;
  size: number;
  createdAt: ISOTimestamp;
  modifiedAt: ISOTimestamp;
  checksum: HexBytes;  // SHA-256

  // Optional fields
  description?: string;
  tags?: string[];
  width?: number;
  height?: number;
  duration?: number;
  pageCount?: number;
  author?: string;
}

/**
 * File as stored on server (encrypted)
 */
interface EncryptedFile {
  id: UUID;
  ownerId: UUID;
  folderId: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  wrappedDek: Base64Bytes;
  blobStorageKey: string;
  blobSize: number;
  blobHash: HexBytes;
  signature: SerializedSignature;
  version: number;
  deletedAt?: ISOTimestamp;           // Set when soft-deleted
  permanentDeletionAt?: ISOTimestamp; // When file will be permanently removed
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

/**
 * Deleted file in trash
 */
interface DeletedFile {
  id: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  deletedAt: ISOTimestamp;
  permanentDeletionAt: ISOTimestamp;
}

/**
 * File with decrypted metadata (client-side)
 */
interface DecryptedFile extends Omit<EncryptedFile, "encryptedMetadata" | "metadataNonce"> {
  metadata: FileMetadata;
}

/**
 * File upload request
 */
interface UploadFileRequest {
  folderId: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  wrappedDek: Base64Bytes;
  signature: SerializedSignature;
}

/**
 * File upload response
 */
interface UploadFileResponse {
  file: EncryptedFile;
  uploadUrl: string;  // Pre-signed URL for blob upload
}

/**
 * File access via share grant
 *
 * When accessing a file via share, the response includes both:
 * - Original file fields (for file signature verification)
 * - Share-specific fields (for share grant signature verification and decryption)
 *
 * Clients MUST verify TWO signatures BEFORE decryption:
 * 1. Share grant signature: Verify `share.signature` using `share.grantor.publicKeys`
 * 2. File signature: Verify `signature` using `owner.publicKeys`
 *
 * NOTE: `wrappedDek` vs `share.wrappedKey`:
 * - `wrappedDek`: Original DEK wrapped by folder KEK - used for SIGNATURE VERIFICATION
 * - `share.wrappedKey`: DEK re-wrapped for recipient via KEM - used for DECRYPTION
 */
interface FileShareAccessResponse {
  id: UUID;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;       // For file signature verification
  };
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  blobSize: number;
  blobHash: HexBytes;                 // Part of signature payload
  wrappedDek: Base64Bytes;            // ORIGINAL wrapped DEK (for file signature verification)
  signature: SerializedSignature;     // Owner's signature (MANDATORY verification)
  share: {
    id: UUID;
    grantor: {
      id: UUID;
      publicKeys: UserPublicKeys;     // For share grant signature verification
    };
    wrappedKey: Base64Bytes;          // DEK re-wrapped for recipient (for decryption)
    kemCiphertexts: SerializedKEMCiphertext[];
    permission: Permission;
    expiry: ISOTimestamp | null;      // For share grant signature verification
    createdAt: ISOTimestamp;          // For share grant signature verification
    signature: SerializedSignature;   // Grantor's signature (MANDATORY verification)
  };
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

/**
 * File deletion response (soft delete)
 */
interface DeleteFileResponse {
  message: string;
  deletedAt: ISOTimestamp;
  permanentDeletionAt: ISOTimestamp;
}

/**
 * File restore request
 */
interface RestoreFileRequest {
  targetFolderId: UUID;
}

/**
 * File restore response
 */
interface RestoreFileResponse {
  file: {
    id: UUID;
    folderId: UUID;
    restoredAt: ISOTimestamp;
  };
}

/**
 * File move request
 *
 * Moving a file requires re-wrapping the DEK with the target folder's KEK.
 * Since wrappedDek is part of the file signature payload, a new signature
 * is required.
 *
 * See crypto/05-signature-protocol.md Section 4.1.1 for signature payload.
 */
interface MoveFileRequest {
  targetFolderId: UUID;
  wrappedDek: Base64Bytes;           // DEK re-wrapped with target folder's KEK
  signature: SerializedSignature;    // Owner's signature over updated state
}

/**
 * File move response
 */
interface MoveFileResponse {
  id: UUID;
  folderId: UUID;
  wrappedDek: Base64Bytes;
  updatedAt: ISOTimestamp;
}

/**
 * Trash listing response
 */
interface TrashListResponse {
  items: DeletedFile[];
}
```

### 4.5 Access and Permissions

```typescript
/**
 * Permission levels for share grants
 * Used when creating or updating shares
 */
type Permission = "read" | "write" | "admin";

/**
 * Access level in API responses
 * Extends Permission with "owner" for resource owners
 *
 * IMPORTANT: "owner" is NOT a share permission - it indicates the user
 * owns the resource (owner_id == current_user_id). You cannot grant
 * "owner" permission via sharing.
 */
type AccessLevel = Permission | "owner";

/**
 * Access source - how user has access to a resource
 */
type AccessSource = "owner" | "share";

/**
 * Access information returned in file/folder API responses
 */
interface AccessInfo {
  source: AccessSource;     // How user has access
  permission: AccessLevel;  // Effective permission level
  shareId?: UUID;           // If source is "share", the share grant ID
}
```

### 4.6 Share Grant

```typescript
type ResourceType = "file" | "folder";

/**
 * Share grant as stored on server
 */
interface ShareGrant {
  id: UUID;
  resourceType: ResourceType;
  resourceId: UUID;
  grantorId: UUID;
  granteeId: UUID;
  wrappedKey: Base64Bytes;
  kemCiphertexts: SerializedKEMCiphertext[];
  permission: Permission;
  recursive: boolean;
  expiry: ISOTimestamp | null;
  signature: SerializedSignature;
  createdAt: ISOTimestamp;
}

/**
 * Create share request
 */
interface CreateShareRequest {
  resourceType: ResourceType;
  resourceId: UUID;
  granteeId: UUID;
  wrappedKey: Base64Bytes;
  kemCiphertexts: SerializedKEMCiphertext[];
  permission: Permission;
  recursive?: boolean;
  expiry?: ISOTimestamp;
  signature: SerializedSignature;
}

/**
 * Share with resource details (for UI)
 */
interface ShareWithDetails extends ShareGrant {
  grantor: UserWithPublicKeys;
  grantee: UserWithPublicKeys;
  resource: EncryptedFile | EncryptedFolder;
}
```

### 4.7 Share Link

```typescript
/**
 * Share link for anonymous/URL-based sharing
 */
interface ShareLink {
  id: UUID;
  resourceType: ResourceType;
  resourceId: UUID;
  creatorId: UUID;                   // User who created this share link
  token: string;                    // URL token (e.g., "abc123xyz")
  wrappedKey: Base64Bytes;          // DEK/KEK wrapped for link access
  permission: Permission;
  passwordProtected: boolean;
  passwordSalt?: Base64Bytes;       // Argon2id salt (if protected)
  passwordHash?: Base64Bytes;       // Argon2id hash (if protected)
  expiry: ISOTimestamp | null;
  maxDownloads: number | null;
  downloadCount: number;
  createdAt: ISOTimestamp;
}

/**
 * Create share link request
 *
 * NOTE: Both passwordHash and signature are required:
 * - passwordHash: Required if passwordProtected, for server-side password verification
 * - signature: Always required, creator signs the link parameters
 */
interface CreateShareLinkRequest {
  resourceType: ResourceType;
  resourceId: UUID;
  wrappedKey: Base64Bytes;
  permission: Permission;
  expiry?: ISOTimestamp;
  passwordProtected: boolean;
  passwordSalt?: Base64Bytes;       // Required if passwordProtected
  passwordHash?: Base64Bytes;       // Required if passwordProtected (Argon2id output)
  maxDownloads?: number;
  createdAt: ISOTimestamp;          // Client timestamp (for signature)
  signature: SerializedSignature;   // Creator's signature (required)
}

/**
 * Share link response (after creation)
 */
interface ShareLinkResponse {
  id: UUID;
  link: string;                     // Full URL (e.g., "https://securesharing.com/s/abc123xyz")
  resourceType: ResourceType;
  expiry: ISOTimestamp | null;
  passwordProtected: boolean;
  maxDownloads: number | null;
  downloadCount: number;
  createdAt: ISOTimestamp;
}

/**
 * Share link details (anonymous access, unprotected) - File
 */
interface ShareLinkFileDetails {
  id: UUID;
  resourceType: 'file';
  passwordProtected: false;
  permission: Permission;
  expiry: ISOTimestamp | null;
  expired: boolean;
  downloadCount: number;
  maxDownloads: number | null;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;
  };
  wrappedKey: Base64Bytes;           // DEK wrapped for link access
  createdAt: ISOTimestamp;
  signature: SerializedSignature;
  file: ShareLinkFileInfo;
}

/**
 * Share link details (anonymous access, unprotected) - Folder
 */
interface ShareLinkFolderDetails {
  id: UUID;
  resourceType: 'folder';
  passwordProtected: false;
  permission: Permission;
  expiry: ISOTimestamp | null;
  expired: boolean;
  downloadCount: number;
  maxDownloads: number | null;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;
  };
  wrappedKey: Base64Bytes;           // KEK wrapped for link access
  createdAt: ISOTimestamp;
  signature: SerializedSignature;
  folder: ShareLinkFolderInfo;
}

/**
 * Share link details - discriminated union
 */
type ShareLinkDetails = ShareLinkFileDetails | ShareLinkFolderDetails;

/**
 * Share link details (anonymous access, password-protected before verification)
 */
interface ShareLinkProtectedDetails {
  id: UUID;
  resourceType: ResourceType;
  passwordProtected: true;
  passwordVerified: false;
  passwordSalt: Base64Bytes;
  expiry: ISOTimestamp | null;
  expired: boolean;
}

/**
 * Share link file info (subset of file details)
 *
 * Includes all fields needed for file signature verification.
 * Clients MUST verify file.signature using file.owner.publicKeys
 * BEFORE decrypting the file content.
 *
 * See crypto/05-signature-protocol.md Section 4.1 for file signature spec.
 */
interface ShareLinkFileInfo {
  id: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  wrappedDek: Base64Bytes;           // Original DEK wrapped by folder KEK (for signature verification)
  blobSize: number;
  blobHash: HexBytes;                // SHA-256 of encrypted blob
  signature: SerializedSignature;    // File owner's signature
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;      // File owner's public keys for signature verification
  };
}

/**
 * Share link folder info (subset of folder details)
 *
 * Includes all fields needed for folder signature verification.
 * Clients MUST verify folder.signature using folder.owner.publicKeys
 * BEFORE decrypting the folder KEK.
 *
 * See crypto/05-signature-protocol.md Section 4.4 for folder signature spec.
 */
interface ShareLinkFolderInfo {
  id: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;    // For signature verification
  wrappedKek: Base64Bytes | null;    // Original KEK wrapped by parent KEK (for signature verification)
  signature: SerializedSignature;    // Folder owner's signature
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;      // Folder owner's public keys for signature verification
  };
  itemCount: number;                 // Number of items (files + subfolders)
  createdAt: ISOTimestamp;           // For signature verification
}

/**
 * Password verification request
 */
interface VerifyShareLinkPasswordRequest {
  passwordHash: Base64Bytes;
}

/**
 * Password verification response - File
 *
 * Includes ALL fields needed for signature payload reconstruction.
 * See crypto/05-signature-protocol.md Section 4.6.
 */
interface ShareLinkFileVerificationResponse {
  verified: true;
  sessionToken: string;
  expiresAt: ISOTimestamp;
  // Signature payload fields
  resourceType: 'file';
  permission: 'read';
  expiry: ISOTimestamp | null;
  passwordProtected: true;           // Always true for this response
  maxDownloads: number | null;
  // Verification fields
  owner: {
    id: UUID;                        // = creatorId in signature payload
    publicKeys: UserPublicKeys;
  };
  wrappedKey: Base64Bytes;           // DEK wrapped with password-derived key
  createdAt: ISOTimestamp;
  signature: SerializedSignature;
  file: ShareLinkFileInfo;           // file.id = resourceId in signature payload
}

/**
 * Password verification response - Folder
 *
 * Includes ALL fields needed for signature payload reconstruction.
 * See crypto/05-signature-protocol.md Section 4.6.
 */
interface ShareLinkFolderVerificationResponse {
  verified: true;
  sessionToken: string;
  expiresAt: ISOTimestamp;
  // Signature payload fields
  resourceType: 'folder';
  permission: 'read';
  expiry: ISOTimestamp | null;
  passwordProtected: true;           // Always true for this response
  maxDownloads: number | null;
  // Verification fields
  owner: {
    id: UUID;                        // = creatorId in signature payload
    publicKeys: UserPublicKeys;
  };
  wrappedKey: Base64Bytes;           // KEK wrapped with password-derived key
  createdAt: ISOTimestamp;
  signature: SerializedSignature;
  folder: ShareLinkFolderInfo;       // folder.id = resourceId in signature payload
}

/**
 * Password verification response - discriminated union
 */
type ShareLinkVerificationResponse =
  | ShareLinkFileVerificationResponse
  | ShareLinkFolderVerificationResponse;

/**
 * Share link download response
 */
interface ShareLinkDownloadResponse {
  download: {
    url: string;
    method: "GET";
    headers: Record<string, string>;
    expiresAt: ISOTimestamp;
  };
  file: {
    id: UUID;
    blobSize: number;
    blobHash: HexBytes;
  };
  downloadCount: number;
  maxDownloads: number | null;
}

/**
 * Folder share link contents response
 *
 * All items include signature and owner fields for verification.
 * Clients MUST verify signatures before trusting metadata or keys.
 */
interface ShareLinkFolderContentsResponse {
  folder: ShareLinkFolderItem;
  path: string;
  items: {
    files: ShareLinkFolderFileItem[];
    subfolders: ShareLinkFolderSubfolderItem[];
  };
}

/**
 * Current folder info in share link contents response
 *
 * Includes all fields needed for folder signature verification.
 */
interface ShareLinkFolderItem {
  id: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;
  signature: SerializedSignature;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;
  };
  createdAt: ISOTimestamp;
}

/**
 * File item within a folder share link
 *
 * Includes all fields needed for file signature verification.
 * Clients MUST verify signature using owner.publicKeys
 * BEFORE decrypting the file content.
 *
 * See crypto/05-signature-protocol.md Section 4.1 for file signature spec.
 */
interface ShareLinkFolderFileItem {
  id: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  wrappedDek: Base64Bytes;           // DEK wrapped by folder KEK
  blobSize: number;
  blobHash: HexBytes;
  signature: SerializedSignature;    // File owner's signature
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;      // File owner's public keys for signature verification
  };
}

/**
 * Subfolder item within a folder share link
 *
 * Includes all fields needed for folder signature verification.
 * Clients MUST verify signature using owner.publicKeys
 * BEFORE trusting metadata or KEK.
 *
 * See crypto/05-signature-protocol.md Section 4.4 for folder signature spec.
 */
interface ShareLinkFolderSubfolderItem {
  id: UUID;
  parentId: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes;           // Subfolder KEK wrapped by parent KEK
  signature: SerializedSignature;    // Subfolder owner's signature
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;      // Subfolder owner's public keys for signature verification
  };
  itemCount: number;
  createdAt: ISOTimestamp;
}
```

### 4.8 Recovery

```typescript
type RecoveryStatus = "pending" | "approved" | "completed" | "expired" | "cancelled";
type RecoveryReason = "device_lost" | "passkey_unavailable" | "credential_reset" | "admin_request";

/**
 * Recovery share held by trustee
 */
interface RecoveryShare {
  id: UUID;
  userId: UUID;
  trusteeId: UUID;
  shareIndex: number;
  encryptedShare: {
    wrappedValue: Base64Bytes;
    kemCiphertexts: SerializedKEMCiphertext[];
  };
  userSignature: SerializedSignature;
  trusteeAcknowledgment?: SerializedSignature;
  acknowledgedAt?: ISOTimestamp;
  createdAt: ISOTimestamp;
}

/**
 * Recovery request
 */
interface RecoveryRequest {
  id: UUID;
  userId: UUID;
  status: RecoveryStatus;
  reason: RecoveryReason;
  verificationMethod: string;
  newPublicKeys: SerializedPublicKeys;
  approvalsRequired: number;
  approvalsReceived: number;
  expiresAt: ISOTimestamp;
  completedAt?: ISOTimestamp;
  createdAt: ISOTimestamp;
}

/**
 * Recovery approval from trustee
 */
interface RecoveryApproval {
  id: UUID;
  requestId: UUID;
  trusteeId: UUID;
  shareIndex: number;
  reencryptedShare: {
    wrappedValue: Base64Bytes;
    kemCiphertexts: SerializedKEMCiphertext[];
  };
  signature: SerializedSignature;
  createdAt: ISOTimestamp;
}
```

## 5. IdP Types

```typescript
type IdpType = "webauthn" | "digital_id" | "oidc" | "saml";

interface IdpConfig {
  id: UUID;
  tenantId: UUID;
  type: IdpType;
  name: string;
  enabled: boolean;
  priority: number;

  /**
   * Whether this IdP provides unique key material for MK encryption.
   * - true: Credentials store MK in Credential.encryptedMasterKey
   *         (WebAuthn always true; Digital ID configurable)
   * - false: Credentials use User.vaultEncryptedMasterKey
   *         (OIDC/SAML always false; Digital ID configurable)
   */
  providesKeyMaterial: boolean;

  config: WebAuthnConfig | DigitalIdConfig | OidcConfig | SamlConfig;
  createdAt: ISOTimestamp;
  updatedAt: ISOTimestamp;
}

interface WebAuthnConfig {
  rpId: string;
  rpName: string;
  attestation: "none" | "indirect" | "direct";
  userVerification: "required" | "preferred" | "discouraged";
}

interface DigitalIdConfig {
  provider: "mydigital_my" | "singpass_sg" | "custom";
  apiEndpoint: string;
  clientId: string;
  certificateFingerprint: string;
}

interface OidcConfig {
  issuer: string;
  clientId: string;
  clientSecret: string;  // Encrypted at rest
  scopes: string[];
  additionalParams?: Record<string, string>;
}

interface SamlConfig {
  entityId: string;
  ssoUrl: string;
  certificate: string;
  signRequests: boolean;
}
```

## 6. Audit Types

```typescript
type AuditEventType =
  | "user.login"
  | "user.logout"
  | "user.register"
  | "file.upload"
  | "file.download"
  | "file.delete"
  | "folder.create"
  | "folder.delete"
  | "share.create"
  | "share.revoke"
  | "share_link.create"
  | "share_link.access"
  | "share_link.download"
  | "share_link.revoke"
  | "recovery.request"
  | "recovery.approve"
  | "recovery.complete";

interface AuditEvent {
  id: UUID;
  tenantId: UUID;
  userId?: UUID;
  eventType: AuditEventType;
  resourceType?: string;
  resourceId?: UUID;
  details: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  timestamp: ISOTimestamp;
}

/**
 * Audit query filters
 */
interface AuditQueryParams {
  userId?: UUID;
  eventType?: AuditEventType | AuditEventType[];
  resourceType?: string;
  resourceId?: UUID;
  startTime?: ISOTimestamp;
  endTime?: ISOTimestamp;
  limit?: number;
  offset?: number;
}
```

## 7. API Response Types

```typescript
/**
 * Standard API response wrapper
 */
interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: ApiError;
}

interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

/**
 * Paginated response
 */
interface PaginatedResponse<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}

/**
 * Folder contents response
 *
 * Includes owner public keys for signature verification on all items.
 * Clients MUST verify signatures before trusting metadata or keys.
 */
interface FolderContentsResponse {
  folder: FolderContentsItem;
  subfolders: FolderContentsItem[];
  files: FileContentsItem[];
  shares: ShareGrant[];
}

/**
 * Folder item in contents response (includes owner keys for signature verification)
 */
interface FolderContentsItem {
  id: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;
  signature: SerializedSignature;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;    // For signature verification
  };
  itemCount: number;
  createdAt: ISOTimestamp;
}

/**
 * File item in contents response (includes owner keys for signature verification)
 */
interface FileContentsItem {
  id: UUID;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  wrappedDek: Base64Bytes;
  blobSize: number;
  blobHash: HexBytes;
  signature: SerializedSignature;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;    // For signature verification
  };
}

/**
 * Folder share access response
 *
 * Includes all fields needed for both folder and share grant signature verification.
 *
 * Clients MUST verify TWO signatures BEFORE decryption:
 * 1. Share grant signature: Verify `share.signature` using `share.grantor.publicKeys`
 * 2. Folder signature: Verify `signature` using `owner.publicKeys`
 *
 * NOTE: `wrappedKek` vs `share.wrappedKey`:
 * - `wrappedKek`: Original KEK wrapped by parent's KEK - for SIGNATURE VERIFICATION
 * - `share.wrappedKey`: KEK re-wrapped for recipient via KEM - for DECRYPTION
 */
interface FolderShareAccessResponse {
  id: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;         // Original (for folder signature verification)
  signature: SerializedSignature;         // Folder owner's signature
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;           // For folder signature verification
  };
  createdAt: ISOTimestamp;
  share: {
    id: UUID;
    grantor: {
      id: UUID;
      publicKeys: UserPublicKeys;         // For share grant signature verification
    };
    wrappedKey: Base64Bytes;              // KEK re-wrapped for recipient (for decryption)
    kemCiphertexts: SerializedKEMCiphertext[];
    permission: Permission;
    recursive: boolean;
    expiry: ISOTimestamp | null;          // For share grant signature verification
    createdAt: ISOTimestamp;              // For share grant signature verification
    signature: SerializedSignature;       // Grantor's signature (MANDATORY verification)
  };
}

/**
 * Folder path response
 *
 * Returns all folders from root to target for breadcrumb navigation.
 * Each folder includes signature verification fields.
 * Clients MUST verify signatures for each folder before trusting metadata or keys.
 */
interface FolderPathResponse {
  path: FolderPathItem[];
}

/**
 * Folder item in path response (includes all signature verification fields)
 */
interface FolderPathItem {
  id: UUID;
  parentId: UUID | null;
  encryptedMetadata: Base64Bytes;
  metadataNonce: Base64Bytes;
  ownerKeyAccess: OwnerKeyAccess;
  wrappedKek: Base64Bytes | null;         // null for root folder
  signature: SerializedSignature;
  owner: {
    id: UUID;
    publicKeys: UserPublicKeys;           // For signature verification
  };
  isRoot: boolean;
  createdAt: ISOTimestamp;
}

/**
 * Shared folders response
 *
 * Lists all folders shared with the current user.
 * Each folder includes signature verification fields.
 * Clients MUST verify folder.signature using folder.owner.publicKeys
 * BEFORE decrypting the folder KEK.
 */
interface SharedFoldersResponse {
  items: SharedFolderItem[];
}

/**
 * Shared folder item (includes signature verification fields)
 *
 * NOTE: `folder.wrappedKek` vs `share.wrappedKey`:
 * - `folder.wrappedKek`: Original KEK wrapped by parent's KEK - for SIGNATURE VERIFICATION
 * - `share.wrappedKey`: KEK re-wrapped for recipient via KEM - for DECRYPTION
 *
 * Recipients verify the signature using `folder.wrappedKek`, then decrypt using `share.wrappedKey`.
 */
interface SharedFolderItem {
  folder: {
    id: UUID;
    parentId: UUID;                       // For signature verification
    encryptedMetadata: Base64Bytes;
    metadataNonce: Base64Bytes;
    ownerKeyAccess: OwnerKeyAccess;       // For signature verification
    wrappedKek: Base64Bytes;              // For signature verification
    signature: SerializedSignature;
    owner: {
      id: UUID;
      publicKeys: UserPublicKeys;         // For signature verification
    };
    createdAt: ISOTimestamp;              // For signature verification
  };
  share: {
    id: UUID;
    grantorId: UUID;
    wrappedKey: Base64Bytes;              // KEK re-wrapped for recipient (for decryption)
    kemCiphertexts: SerializedKEMCiphertext[];
    permission: Permission;
    recursive: boolean;
    createdAt: ISOTimestamp;
  };
  grantor: {
    id: UUID;
    email: string;
    displayName?: string;
  };
}
```

## 8. Crypto SDK Interface

```typescript
/**
 * Main crypto SDK interface
 */
interface SecureSharingCrypto {
  // Key generation
  generateUserKeySet(): Promise<UserKeySet>;
  generateDEK(): Promise<DEK>;
  generateKEK(): Promise<KEK>;

  // File encryption
  encryptFile(
    plaintext: Uint8Array | ReadableStream<Uint8Array>,
    folderKek: KEK,
    options?: EncryptionOptions
  ): Promise<EncryptedFilePackage>;

  decryptFile(
    encryptedPackage: EncryptedFilePackage,
    dek: DEK
  ): Promise<DecryptedFileResult>;

  // Key operations
  encapsulateKey(
    key: Uint8Array,
    recipientPublicKeys: PublicKeySet
  ): Promise<KeyEncapsulationResult>;

  decapsulateKey(
    wrapped: KeyEncapsulationResult,
    privateKeys: UserKeySet
  ): Promise<Uint8Array>;

  // Signatures
  sign(message: Uint8Array, signKeys: UserKeySet): Promise<CombinedSignature>;
  verify(
    message: Uint8Array,
    signature: CombinedSignature,
    publicKeys: PublicKeySet
  ): Promise<boolean>;

  // Shamir
  splitSecret(
    secret: Uint8Array,
    threshold: number,
    shares: number
  ): Promise<ShamirShare[]>;

  reconstructSecret(shares: ShamirShare[]): Promise<Uint8Array>;
}

interface EncryptionOptions {
  chunkSize?: number;
  onProgress?: (progress: EncryptionProgress) => void;
}

interface EncryptionProgress {
  bytesProcessed: number;
  totalBytes: number;
  chunksProcessed: number;
  totalChunks: number;
}

interface EncryptedFilePackage {
  header: Uint8Array;
  chunks: AsyncIterable<Uint8Array>;
  wrappedDek: Uint8Array;
  encryptedMetadata: Uint8Array;
  metadataNonce: Uint8Array;
}

interface DecryptedFileResult {
  content: Uint8Array | ReadableStream<Uint8Array>;
  metadata: FileMetadata;
}

interface KeyEncapsulationResult {
  wrappedKey: Uint8Array;
  kemCiphertexts: KEMCiphertext[];
}

interface ShamirShare {
  index: number;
  value: Uint8Array;
}
```

## 9. Type Guards

```typescript
/**
 * Type guard for file vs folder
 */
function isFile(resource: EncryptedFile | EncryptedFolder): resource is EncryptedFile {
  return "wrappedDek" in resource;
}

function isFolder(resource: EncryptedFile | EncryptedFolder): resource is EncryptedFolder {
  return "isRoot" in resource;
}

/**
 * Type guard for share expiry
 */
function isShareExpired(share: ShareGrant): boolean {
  if (!share.expiry) return false;
  return new Date(share.expiry) < new Date();
}

/**
 * Type guard for soft-deleted file
 */
function isFileDeleted(file: EncryptedFile): boolean {
  return file.deletedAt !== undefined;
}

/**
 * Type guard for file pending permanent deletion
 */
function isFilePendingPermanentDeletion(file: EncryptedFile): boolean {
  return file.permanentDeletionAt !== undefined &&
         new Date(file.permanentDeletionAt) > new Date();
}

/**
 * Type guard for recovery status
 */
function isRecoveryActive(request: RecoveryRequest): boolean {
  return request.status === "pending" || request.status === "approved";
}
```
