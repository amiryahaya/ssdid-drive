# File & Directory Sharing Permission Model

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-02-07
**Authors**: SecureSharing Team

## 1. Overview

This document defines the complete sharing permission model for SecureSharing, including:

- Permission levels and their enforcement
- Encryption key handling during file updates by non-owners
- Ownership semantics and transfer
- Audit logging requirements
- Folder-specific permissions and inheritance

This is a **core specification document** that should be read alongside:
- [Architecture Overview](./01-architecture-overview.md)
- [Key Hierarchy](../crypto/02-key-hierarchy.md)
- [Sharing API](../api/05-sharing.md)

---

## 2. Permission Hierarchy

### 2.1 Permission Levels

SecureSharing defines four access levels, in ascending order of privileges:

| Level | Value | Description |
|-------|-------|-------------|
| **Read** | `:read` | Can decrypt and view content |
| **Write** | `:write` | Can read + modify content |
| **Admin** | `:admin` | Can write + share with others + manage shares |
| **Owner** | `:owner` | Full control including delete and ownership transfer |

> **Note**: `:owner` is NOT a shareable permission. It represents the original creator of the resource. Only `:read`, `:write`, and `:admin` can be granted via shares.

### 2.2 Permission Inheritance

Permissions are inherited through the folder hierarchy:

```
Folder A (admin) ──┬── Folder B (inherits admin)
                   │       └── File X (inherits admin)
                   └── File Y (inherits admin)
```

When a user has a share on a folder with `recursive: true`, they inherit that permission level for all children.

**Explicit shares override inherited permissions:**
- User has `:read` on Folder A (recursive)
- User has explicit `:write` share on File X
- Result: User has `:write` on File X, `:read` on everything else in Folder A

---

## 3. File Permissions

### 3.1 File Permission Matrix

| Action | Owner | Admin | Write | Read |
|--------|:-----:|:-----:|:-----:|:----:|
| Download / View | ✅ | ✅ | ✅ | ✅ |
| Update content (re-encrypt) | ✅ | ✅ | ✅ | ❌ |
| Update encrypted metadata | ✅ | ✅ | ✅ | ❌ |
| Share with others | ✅ | ✅ | ❌ | ❌ |
| Revoke shares (any) | ✅ | ❌ | ❌ | ❌ |
| Revoke shares (self-created) | ✅ | ✅ | ❌ | ❌ |
| Delete file | ✅ | ✅ | ❌ | ❌ |
| Transfer ownership | ✅ | ❌ | ❌ | ❌ |
| View audit logs | ✅ | ✅ | ❌ | ❌ |

### 3.2 File Fields

```elixir
schema "files" do
  belongs_to :tenant, Tenant
  belongs_to :owner, User              # Original creator, immutable unless transferred
  belongs_to :folder, Folder           # Parent folder (nil = root)

  # Content
  field :storage_path, :string         # S3/Garage path
  field :blob_size, :integer
  field :blob_hash, :binary            # SHA-256 of encrypted blob

  # Encrypted metadata (filename, mime type, etc.)
  field :encrypted_metadata, :binary
  field :metadata_nonce, :binary

  # Encryption keys
  field :wrapped_dek, :binary          # DEK wrapped for owner's KEM public key
  field :kem_ciphertext, :binary       # KEM ciphertext for DEK unwrapping

  # Integrity
  field :signature, :binary            # Owner's signature over file data

  # Tracking
  field :status, Ecto.Enum             # :pending, :uploading, :complete, :failed
  field :updated_by_id, :binary_id     # Last user who modified content (NEW)

  timestamps(type: :utc_datetime_usec)
end
```

---

## 4. Folder Permissions

### 4.1 Folder Permission Matrix

| Action | Owner | Admin | Write | Read |
|--------|:-----:|:-----:|:-----:|:----:|
| List contents | ✅ | ✅ | ✅ | ✅ |
| Read files inside | ✅ | ✅ | ✅ | ✅ |
| Add files to folder | ✅ | ✅ | ✅ | ❌ |
| Create subfolders | ✅ | ✅ | ✅ | ❌ |
| Rename folder | ✅ | ✅ | ❌ | ❌ |
| Move folder | ✅ | ✅ | ❌ | ❌ |
| Delete files inside | ✅ | ✅ | ❌ | ❌ |
| Delete subfolders | ✅ | ✅ | ❌ | ❌ |
| Delete folder itself | ✅ | ✅ | ❌ | ❌ |
| Share folder | ✅ | ✅ | ❌ | ❌ |
| Revoke shares (any) | ✅ | ❌ | ❌ | ❌ |
| Revoke shares (self-created) | ✅ | ✅ | ❌ | ❌ |
| Transfer ownership | ✅ | ❌ | ❌ | ❌ |

### 4.2 Write Permission Rationale

**Write permission allows adding but NOT deleting:**
- Prevents accidental data loss by collaborators
- Write users can contribute content but cannot remove existing work
- Admin permission required for destructive operations

### 4.3 Folder Fields

```elixir
schema "folders" do
  belongs_to :tenant, Tenant
  belongs_to :owner, User              # Original creator
  belongs_to :parent, Folder           # Parent folder (nil = root)

  # Encrypted metadata (folder name, color, icon, etc.)
  field :encrypted_metadata, :binary
  field :metadata_nonce, :binary

  # Folder key (KEK)
  field :wrapped_kek, :binary          # KEK wrapped for owner's KEM public key
  field :kem_ciphertext, :binary       # KEM ciphertext for KEK unwrapping

  # Integrity
  field :signature, :binary            # Owner's signature

  timestamps(type: :utc_datetime_usec)
end
```

---

## 5. Encryption Key Handling

### 5.1 Core Principle: DEK Stays the Same

When a non-owner modifies a file, the Data Encryption Key (DEK) **does not change**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FILE UPDATE BY NON-OWNER                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. User B (with :write permission) wants to edit                   │
│     └─> Has wrapped_key from their ShareGrant                      │
│     └─> Decapsulates using their private KEM key → gets DEK        │
│                                                                     │
│  2. User B decrypts file content with DEK                           │
│     └─> Modifies content                                            │
│     └─> Re-encrypts with SAME DEK                                   │
│     └─> Computes new blob_hash                                      │
│                                                                     │
│  3. User B uploads new encrypted blob                               │
│     └─> Updates: blob_hash, blob_size, updated_at, updated_by_id   │
│     └─> Owner stays: User A (unchanged)                             │
│     └─> DEK stays: same (all shares still work)                     │
│                                                                     │
│  4. All other share recipients can still decrypt                    │
│     └─> Their wrapped_key is still valid for the same DEK          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Why DEK Stays the Same

1. **All shares remain valid**: Other recipients' `wrapped_key` entries still work
2. **No key redistribution**: Owner doesn't need to re-wrap DEK for every recipient
3. **Zero-knowledge preserved**: Server never sees the DEK
4. **Audit trail maintained**: `updated_by_id` tracks who made changes

### 5.3 Signature Handling on Update

When a non-owner updates file content:

| Field | Behavior | Reason |
|-------|----------|--------|
| `signature` | **Updated by editor** | Signs new content hash |
| `blob_hash` | Updated | New encrypted content |
| `blob_size` | Updated | May change |
| `updated_by_id` | Set to editor's ID | Audit tracking |
| `owner_id` | **Unchanged** | Original creator stays |
| `wrapped_dek` | **Unchanged** | Same key for all shares |

**Signature Verification Chain:**
- Clients verify `signature` against `updated_by_id`'s public key (most recent edit)
- Optionally verify against `owner_id`'s key for original creation
- Audit log provides full signature history

### 5.4 Folder KEK Handling

For folders, the Key Encryption Key (KEK) also stays constant:

- Users with `:write` on a folder can add new files
- New files get DEKs wrapped with the folder's KEK
- Share recipients can decrypt new files without new shares

---

## 6. Ownership Model

### 6.1 Owner Never Changes (Default)

The `owner_id` field represents the original creator and provides:
- Ultimate control over the resource
- Ability to revoke any share (including admin shares)
- Ability to delete the resource
- Single point of accountability

**Ownership does NOT change when:**
- Someone else edits the content
- Someone else adds files to a folder
- Shares are created or modified

### 6.2 Ownership Transfer (Explicit)

Ownership can only be transferred through an explicit action:

```http
POST /api/files/{id}/transfer-ownership
Authorization: Bearer <token>
Content-Type: application/json

{
  "new_owner_id": "uuid",
  "signature": "base64..."  # Owner signs the transfer
}
```

**Transfer Process:**
1. Current owner initiates transfer
2. System creates new `wrapped_dek` for new owner's public key
3. Old owner's direct access is converted to an admin share (optional)
4. All existing shares remain valid
5. Audit log records the transfer

### 6.3 Owner Responsibilities

| Responsibility | Description |
|---------------|-------------|
| Key custody | Owner's `wrapped_dek` is the primary key access |
| Share management | Can revoke any share at any time |
| Deletion authority | Only owner/admin can delete resources |
| Audit accountability | All changes traced back to owner's resource |

---

## 7. Audit Logging Requirements

### 7.1 Audit Log Schema

```elixir
schema "audit_logs" do
  belongs_to :tenant, Tenant
  belongs_to :actor, User              # Who performed the action
  belongs_to :resource_owner, User     # Original owner of the resource

  field :action, Ecto.Enum, values: [
    # File actions
    :file_created, :file_updated, :file_downloaded, :file_deleted,
    :file_moved, :file_ownership_transferred,
    # Folder actions
    :folder_created, :folder_updated, :folder_deleted,
    :folder_moved, :folder_ownership_transferred,
    # Share actions
    :share_created, :share_updated, :share_revoked,
    :share_permission_upgraded, :share_permission_downgraded,
    # Access
    :access_granted, :access_denied
  ]

  field :resource_type, Ecto.Enum, values: [:file, :folder, :share]
  field :resource_id, :binary_id

  # How the actor accessed the resource
  field :access_via, Ecto.Enum, values: [:owner, :share_grant, :folder_share, :link]
  field :share_grant_id, :binary_id    # If accessed via share
  field :permission_used, Ecto.Enum    # :read, :write, :admin

  # Change details
  field :changes, :map                 # {field: [old, new], ...}
  field :metadata, :map                # Additional context

  # Integrity
  field :signature, :binary            # Actor signs the audit entry

  timestamps(type: :utc_datetime_usec, updated_at: false)
end
```

### 7.2 Required Audit Events

| Event | Trigger | Required Fields |
|-------|---------|-----------------|
| `file_created` | New file upload complete | actor, resource, owner |
| `file_updated` | Content or metadata change | actor, access_via, share_grant_id, changes |
| `file_downloaded` | Download initiated | actor, access_via, share_grant_id |
| `file_deleted` | File permanently removed | actor, access_via, permission_used |
| `share_created` | New share grant | actor, grantee_id, permission |
| `share_revoked` | Share removed | actor, revoked_share, reason |
| `access_denied` | Permission check failed | actor, attempted_action, reason |

### 7.3 Audit Entry Example

```json
{
  "id": "01234567-89ab-cdef-0123-456789abcdef",
  "tenant_id": "tenant-uuid",
  "actor_id": "user-b-uuid",
  "resource_owner_id": "user-a-uuid",
  "action": "file_updated",
  "resource_type": "file",
  "resource_id": "file-uuid",
  "access_via": "share_grant",
  "share_grant_id": "share-uuid",
  "permission_used": "write",
  "changes": {
    "blob_hash": ["old-hash", "new-hash"],
    "blob_size": [1024, 2048],
    "updated_by_id": [null, "user-b-uuid"]
  },
  "metadata": {
    "client_ip": "192.168.1.1",
    "device_id": "device-uuid",
    "client_version": "1.2.3"
  },
  "signature": "base64...",
  "inserted_at": "2026-02-07T10:30:00.000000Z"
}
```

### 7.4 Audit Log Retention

| Log Type | Retention | Reason |
|----------|-----------|--------|
| Security events | 7 years | Compliance (e.g., ISO 27001) |
| Access logs | 2 years | Operational |
| Content changes | 5 years | Legal discovery |
| Failed access | 1 year | Security monitoring |

---

## 8. Permission Enforcement

### 8.1 Controller-Level Enforcement

All controllers MUST enforce permissions before allowing operations:

```elixir
# FileController - Update action
def update(conn, %{"id" => id} = params) do
  user = conn.assigns.current_user

  with {:ok, file} <- Files.get_file(id),
       # CHANGED: Use can_write_file? instead of verify_owner
       true <- Sharing.can_write_file?(user, file),
       {:ok, updated} <- Files.update_file(file, params, user) do
    render(conn, :show, file: updated)
  end
end

# FileController - Delete action
def delete(conn, %{"id" => id}) do
  user = conn.assigns.current_user

  with {:ok, file} <- Files.get_file(id),
       # Require :admin or :owner for deletion
       true <- Sharing.can_delete_file?(user, file),
       {:ok, _} <- Files.delete_file(file) do
    send_resp(conn, :no_content, "")
  end
end
```

### 8.2 Permission Check Functions

```elixir
defmodule SecureSharing.Sharing do
  @doc """
  Gets the effective permission level for a user on a file.
  Returns :owner, :admin, :write, :read, or nil.
  """
  def get_file_permission(%User{id: user_id} = user, %File{owner_id: owner_id} = file) do
    cond do
      user_id == owner_id -> :owner

      share = get_share_for_user(user, :file, file.id) ->
        share.permission

      file.folder_id && folder_permission = get_folder_permission(user, file.folder_id) ->
        # Inherited from folder, but never higher than :admin
        min(folder_permission, :admin)

      true -> nil
    end
  end

  @doc "Can user read/download the file?"
  def can_read_file?(%User{} = user, %File{} = file) do
    get_file_permission(user, file) != nil
  end

  @doc "Can user modify the file content?"
  def can_write_file?(%User{} = user, %File{} = file) do
    get_file_permission(user, file) in [:owner, :admin, :write]
  end

  @doc "Can user share the file with others?"
  def can_share_file?(%User{} = user, %File{} = file) do
    get_file_permission(user, file) in [:owner, :admin]
  end

  @doc "Can user delete the file?"
  def can_delete_file?(%User{} = user, %File{} = file) do
    get_file_permission(user, file) in [:owner, :admin]
  end
end
```

---

## 9. Share Grant Schema

### 9.1 ShareGrant Fields

```elixir
schema "share_grants" do
  belongs_to :tenant, Tenant
  belongs_to :grantor, User            # Who created the share
  belongs_to :grantee, User            # Who receives access
  belongs_to :revoked_by, User         # Who revoked (if revoked)

  # Resource being shared
  field :resource_type, Ecto.Enum, values: [:file, :folder]
  field :resource_id, :binary_id

  # Cryptographic access (wrapped for grantee's public key)
  field :wrapped_key, :binary          # DEK (file) or KEK (folder)
  field :kem_ciphertext, :binary       # For unwrapping
  field :algorithm, :string            # "kaz", "nist", "hybrid"

  # Permission level
  field :permission, Ecto.Enum, values: [:read, :write, :admin]
  field :recursive, :boolean           # For folders: include children

  # Time constraints
  field :expires_at, :utc_datetime_usec
  field :revoked_at, :utc_datetime_usec

  # Integrity
  field :signature, :binary            # Grantor's signature

  timestamps(type: :utc_datetime_usec)
end
```

### 9.2 Share Lifecycle

```
┌──────────┐     create      ┌──────────┐
│  (none)  │ ───────────────> │  active  │
└──────────┘                  └──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                 revoke         expire      update_permission
                    │              │              │
                    ▼              ▼              ▼
              ┌──────────┐   ┌──────────┐   ┌──────────┐
              │ revoked  │   │ expired  │   │  active  │
              └──────────┘   └──────────┘   └──────────┘
```

### 9.3 Active Share Check

```elixir
def active?(%ShareGrant{revoked_at: revoked_at, expires_at: expires_at}) do
  not_revoked = is_nil(revoked_at)
  not_expired = is_nil(expires_at) or DateTime.compare(expires_at, DateTime.utc_now()) == :gt

  not_revoked and not_expired
end
```

---

## 10. Request Access Flow (Future)

### 10.1 Use Case: Permission Upgrade

A user with `:read` permission wants `:write` access:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    REQUEST ACCESS UPGRADE FLOW                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. User B (has :read) clicks "Request Write Access"               │
│     └─> Creates AccessRequest with requested_permission: :write    │
│                                                                     │
│  2. Owner (User A) sees notification                                │
│     └─> Reviews request in pending requests list                   │
│                                                                     │
│  3. Owner clicks "Approve"                                          │
│     └─> Owner's CLIENT does crypto:                                │
│         • Fetches User B's public KEM key                          │
│         • Re-wraps DEK for User B (same key, new permission)       │
│         • Signs the upgraded share grant                           │
│     └─> Updates ShareGrant with permission: :write                 │
│                                                                     │
│  4. User B receives notification                                    │
│     └─> Can now modify the file                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 10.2 AccessRequest Schema (Future)

```elixir
schema "access_requests" do
  belongs_to :tenant, Tenant
  belongs_to :requester, User
  belongs_to :owner, User              # Resource owner

  field :resource_type, Ecto.Enum
  field :resource_id, :binary_id

  field :current_permission, Ecto.Enum # nil, :read, :write
  field :requested_permission, Ecto.Enum # :read, :write, :admin

  field :message, :string              # Request reason
  field :status, Ecto.Enum             # :pending, :approved, :denied

  field :decided_at, :utc_datetime_usec
  field :denial_reason, :string

  timestamps(type: :utc_datetime_usec)
end
```

---

## 11. Implementation Checklist

### 11.1 Backend Changes Required

- [ ] Add `updated_by_id` field to files table (migration)
- [ ] Update `FileController.update/2` to use `can_write_file?/2`
- [ ] Update `FileController.delete/2` to use `can_delete_file?/2`
- [ ] Add `can_delete_file?/2` function to Sharing module
- [ ] Add `can_delete_folder?/2` function to Sharing module
- [ ] Update folder operations to respect write vs admin permissions
- [ ] Create audit log entries for all file/folder operations
- [ ] Add signature verification for non-owner updates

### 11.2 Audit System Changes

- [ ] Create `audit_logs` table (migration)
- [ ] Create `AuditLog` schema
- [ ] Create `Auditing` context module
- [ ] Add audit hooks to file/folder/share operations
- [ ] Implement audit log querying for owners/admins

### 11.3 API Changes

- [ ] Add `updated_by` to file response JSON
- [ ] Add `GET /api/files/{id}/audit-log` endpoint
- [ ] Add `GET /api/folders/{id}/audit-log` endpoint
- [ ] Add `POST /api/files/{id}/transfer-ownership` endpoint

### 11.4 Client Changes

- [ ] Update file detail view to show `updated_by`
- [ ] Add signature handling for content updates by non-owners
- [ ] Add audit log viewer for file owners
- [ ] Add ownership transfer UI

---

## 12. Security Considerations

### 12.1 Permission Escalation Prevention

- Users cannot grant permissions higher than their own level
- `:admin` cannot grant `:owner` (not a valid share permission)
- Share creation requires signature verification
- Audit logs detect and flag unusual permission patterns

### 12.2 Key Security

- DEK never leaves client unencrypted
- Server never has access to unwrapped keys
- Each share has independently wrapped key
- Revocation doesn't require re-encryption (key rotation optional)

### 12.3 Audit Integrity

- All audit entries are signed by the actor
- Audit logs are append-only (no updates/deletes)
- Timestamps from trusted server clock
- Signature chain prevents tampering

---

## 13. References

- [Architecture Overview](./01-architecture-overview.md)
- [Threat Model](./02-threat-model.md)
- [Key Hierarchy](../crypto/02-key-hierarchy.md)
- [Encryption Protocol](../crypto/03-encryption-protocol.md)
- [Signature Protocol](../crypto/05-signature-protocol.md)
- [Sharing API](../api/05-sharing.md)
- [Share File Flow](../flows/05-share-file-flow.md)
- [Share Folder Flow](../flows/06-share-folder-flow.md)
