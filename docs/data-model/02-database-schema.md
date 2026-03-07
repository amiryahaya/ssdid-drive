# Database Schema (PostgreSQL 18)

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

This document provides the PostgreSQL DDL for SecureSharing. The schema is designed for:
- Multi-tenant isolation
- Efficient queries for common access patterns
- JSON storage for encrypted/flexible data
- Audit trail compliance
- **UUIDv7 primary keys** for time-ordered, sortable identifiers

### Why UUIDv7?

| Feature | UUIDv4 | UUIDv7 |
|---------|--------|--------|
| Ordering | Random | Time-ordered |
| Index performance | Poor (random inserts) | Excellent (sequential inserts) |
| Timestamp extraction | No | Yes (embedded) |
| Sorting by creation | Requires `created_at` | Natural order |

### UUIDv7 Generation Strategy

**App-generated** via Elixir `uuidv7` library (not database-generated).

| Layer | Responsibility |
|-------|----------------|
| Ecto schema | `@primary_key {:id, UUIDv7, autogenerate: true}` generates ID before INSERT |
| Migration | `add :id, :binary_id, primary_key: true` (no DEFAULT) |
| Database | Stores UUID; no generation function needed |

This approach ensures:
- Consistent ID generation across all database backends
- ID available in Ecto changesets before INSERT
- No dependency on PostgreSQL-specific functions

> **Note:** PostgreSQL 18 provides built-in `uuidv7()`, but we don't use it since
> Ecto generates IDs. The DDL examples below omit `DEFAULT uuidv7()` to match
> the actual implementation.

## 2. Extensions

```sql
-- Required extensions
-- Note: uuid-ossp NOT needed; UUIDv7 values are app-generated
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- Cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";        -- Trigram search (optional)
```

## 3. Enums

```sql
-- Tenant status
CREATE TYPE tenant_status AS ENUM ('active', 'suspended', 'deleted');

-- Tenant plan
CREATE TYPE tenant_plan AS ENUM ('free', 'pro', 'enterprise');

-- User status
CREATE TYPE user_status AS ENUM ('active', 'suspended', 'deleted');

-- User role within tenant
CREATE TYPE user_role AS ENUM ('member', 'admin', 'owner');

-- Identity provider type
CREATE TYPE idp_type AS ENUM ('webauthn', 'digital_id', 'oidc', 'saml');

-- Credential type (user authentication method)
CREATE TYPE credential_type AS ENUM ('webauthn', 'digital_id', 'oidc', 'saml');

-- Share resource type
CREATE TYPE resource_type AS ENUM ('file', 'folder');

-- Permission level
CREATE TYPE permission_level AS ENUM ('read', 'write', 'admin');

-- Recovery request status
CREATE TYPE recovery_status AS ENUM ('pending', 'approved', 'completed', 'expired', 'cancelled');

-- Recovery reason
CREATE TYPE recovery_reason AS ENUM ('device_lost', 'passkey_unavailable', 'credential_reset', 'admin_request');
```

## 4. Tables

### 4.1 Tenants

```sql
CREATE TABLE tenants (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Identity
    name VARCHAR(256) NOT NULL,
    slug VARCHAR(64) NOT NULL UNIQUE,

    -- Status
    status tenant_status NOT NULL DEFAULT 'active',
    plan tenant_plan NOT NULL DEFAULT 'free',

    -- Limits
    storage_quota_bytes BIGINT NOT NULL DEFAULT 10737418240, -- 10 GiB
    max_users INTEGER NOT NULL DEFAULT 10,

    -- Configuration
    settings JSONB NOT NULL DEFAULT '{}',

    -- Billing
    billing_email VARCHAR(256),
    stripe_customer_id VARCHAR(256),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_tenants_slug ON tenants(slug);
CREATE INDEX idx_tenants_status ON tenants(status);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.2 Users

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Identity
    external_id VARCHAR(256),
    email VARCHAR(256) NOT NULL,
    display_name VARCHAR(256),

    -- Status
    status user_status NOT NULL DEFAULT 'active',
    role user_role NOT NULL DEFAULT 'member',

    -- Cryptographic material (vault-based MK storage)
    -- See "Master Key Storage Model (Credential-Authoritative)" in 01-entities.md.
    --
    -- LOGIN PRECEDENCE RULE:
    -- These vault_* fields are used ONLY when authenticating with a credential whose
    -- IdpConfig.provides_key_material = false (OIDC, SAML, OIDC-based Digital ID).
    -- When authenticating with a credential that HAS key material (WebAuthn, cert-based
    -- Digital ID), use Credential.encrypted_master_key instead.
    --
    -- NULL if user only has credentials WITH key material (WebAuthn, cert-based Digital ID).
    -- MUST be non-NULL if user has ANY credential WITHOUT key material.
    vault_encrypted_master_key BYTEA,       -- MK encrypted with vault password-derived key
    vault_mk_nonce BYTEA,                   -- Nonce for vault MK encryption (AES-256-GCM)
    vault_salt BYTEA,                       -- Salt for Argon2id(vault_password)
    public_keys JSONB NOT NULL,
    encrypted_private_keys JSONB NOT NULL,

    -- Recovery
    recovery_setup_complete BOOLEAN NOT NULL DEFAULT FALSE,

    -- Metadata
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(tenant_id, email)
);

-- Indexes
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_tenant_status ON users(tenant_id, status);
CREATE INDEX idx_users_email ON users(email);

-- Trigger
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.3 User Tenants (Multi-Tenant User Support)

> **Status**: Planned - See [Multi-Tenant Users Feature](../features/multi-tenant-users.md)

This table enables users to belong to multiple tenants with per-tenant roles.

```sql
CREATE TABLE user_tenants (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7)

    -- Relationships
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Role within this tenant
    role user_role NOT NULL DEFAULT 'member',

    -- Invitation tracking
    invited_by UUID REFERENCES users(id) ON DELETE SET NULL,
    invitation_accepted_at TIMESTAMPTZ,

    -- Status
    status VARCHAR(32) NOT NULL DEFAULT 'active',  -- active, suspended, pending

    -- Timestamps
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id, tenant_id)
);

-- Indexes
CREATE INDEX idx_user_tenants_user ON user_tenants(user_id);
CREATE INDEX idx_user_tenants_tenant ON user_tenants(tenant_id);
CREATE INDEX idx_user_tenants_tenant_role ON user_tenants(tenant_id, role);

-- Trigger
CREATE TRIGGER user_tenants_updated_at
    BEFORE UPDATE ON user_tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

**Migration Note**: When implementing multi-tenant users:
1. Create `user_tenants` table
2. Migrate existing `users.tenant_id` and `users.role` to `user_tenants`
3. Make `users.tenant_id` nullable, then drop it
4. Move `users.role` to `user_tenants`

### 4.4 IdP Configurations

```sql
CREATE TABLE idp_configs (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Configuration
    type idp_type NOT NULL,
    name VARCHAR(128) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    priority INTEGER NOT NULL DEFAULT 0,

    -- Key material capability
    -- Determines where MK is stored for credentials using this IdP.
    -- true: Credential.encrypted_master_key (WebAuthn, cert-based Digital ID)
    -- false: User.vault_encrypted_master_key (OIDC, SAML, OIDC-based Digital ID)
    provides_key_material BOOLEAN NOT NULL DEFAULT FALSE,

    config JSONB NOT NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_idp_configs_tenant ON idp_configs(tenant_id, enabled, priority);

-- Trigger
CREATE TRIGGER idp_configs_updated_at
    BEFORE UPDATE ON idp_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.4 Credentials

```sql
CREATE TABLE credentials (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id UUID REFERENCES idp_configs(id) ON DELETE SET NULL,

    -- Type
    type credential_type NOT NULL,

    -- WebAuthn-specific
    credential_id BYTEA,           -- WebAuthn credential ID
    public_key BYTEA,              -- WebAuthn public key (COSE format)
    counter INTEGER NOT NULL DEFAULT 0,
    transports JSONB,              -- ["internal", "hybrid", etc.]

    -- OIDC/Digital ID specific
    external_id VARCHAR(256),      -- Subject ID from IdP

    -- Credential-level MK storage (for IdPs with key material)
    -- See "Master Key Storage Model (Credential-Authoritative)" in 01-entities.md.
    --
    -- LOGIN PRECEDENCE RULE:
    -- MK source is determined by the credential being used to authenticate:
    --   IF IdpConfig.provides_key_material = true  → Use THIS credential's encrypted_master_key
    --   IF IdpConfig.provides_key_material = false → Use User.vault_encrypted_master_key
    --
    -- Populated when IdpConfig.provides_key_material = true (WebAuthn, cert-based Digital ID).
    -- NULL when IdpConfig.provides_key_material = false (uses User.vault_encrypted_master_key).
    encrypted_master_key BYTEA,    -- MK encrypted with this credential's key material
    mk_nonce BYTEA,                -- Nonce for MK encryption (AES-256-GCM)

    -- Metadata
    device_name VARCHAR(128),
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT credentials_webauthn_check CHECK (
        type != 'webauthn' OR (credential_id IS NOT NULL AND public_key IS NOT NULL)
    ),
    CONSTRAINT credentials_oidc_check CHECK (
        type NOT IN ('oidc', 'digital_id') OR external_id IS NOT NULL
    )
);

-- Indexes
CREATE INDEX idx_credentials_user ON credentials(user_id, type);
CREATE INDEX idx_credentials_credential_id ON credentials(credential_id) WHERE credential_id IS NOT NULL;
CREATE INDEX idx_credentials_external_id ON credentials(external_id) WHERE external_id IS NOT NULL;

-- Unique constraint: one credential_id per tenant (via user)
CREATE UNIQUE INDEX idx_credentials_unique_webauthn ON credentials(credential_id)
    WHERE credential_id IS NOT NULL;
```

### 4.5 Folders

```sql
CREATE TABLE folders (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES folders(id) ON DELETE CASCADE,

    -- Encrypted data
    encrypted_metadata BYTEA NOT NULL,
    metadata_nonce BYTEA NOT NULL,

    -- KEK management
    owner_key_access JSONB NOT NULL,
    wrapped_kek BYTEA, -- NULL for root folder

    -- Cryptographic integrity
    -- Owner's signature over folder creation (see crypto/05-signature-protocol.md Section 4.4)
    signature JSONB NOT NULL,
    -- { ml_dsa: Base64, kaz_sign: Base64 }

    -- Metadata
    is_root BOOLEAN NOT NULL DEFAULT FALSE,
    item_count INTEGER NOT NULL DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_folders_owner ON folders(owner_id);
CREATE INDEX idx_folders_parent ON folders(parent_id);
CREATE INDEX idx_folders_owner_root ON folders(owner_id, is_root) WHERE is_root = TRUE;

-- Constraint: only one root folder per user
CREATE UNIQUE INDEX idx_folders_unique_root ON folders(owner_id) WHERE is_root = TRUE;

-- Trigger
CREATE TRIGGER folders_updated_at
    BEFORE UPDATE ON folders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Function to check for circular references
CREATE OR REPLACE FUNCTION check_folder_acyclic()
RETURNS TRIGGER AS $$
DECLARE
    current_id UUID;
    visited UUID[];
BEGIN
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    current_id := NEW.parent_id;
    visited := ARRAY[NEW.id];

    WHILE current_id IS NOT NULL LOOP
        IF current_id = ANY(visited) THEN
            RAISE EXCEPTION 'Circular folder reference detected';
        END IF;
        visited := visited || current_id;
        SELECT parent_id INTO current_id FROM folders WHERE id = current_id;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER folders_acyclic_check
    BEFORE INSERT OR UPDATE ON folders
    FOR EACH ROW EXECUTE FUNCTION check_folder_acyclic();
```

### 4.6 Files

```sql
CREATE TABLE files (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    folder_id UUID NOT NULL REFERENCES folders(id) ON DELETE CASCADE,

    -- Encrypted data
    encrypted_metadata BYTEA NOT NULL,
    metadata_nonce BYTEA NOT NULL,

    -- DEK management
    wrapped_dek BYTEA NOT NULL,

    -- Blob storage
    blob_storage_key VARCHAR(512) NOT NULL,
    blob_size BIGINT NOT NULL,
    blob_hash CHAR(64) NOT NULL, -- SHA-256 hex

    -- Signature
    signature JSONB NOT NULL,

    -- Version
    version INTEGER NOT NULL DEFAULT 1,

    -- Soft delete
    deleted_at TIMESTAMPTZ,              -- NULL = active, set = soft deleted
    permanent_deletion_at TIMESTAMPTZ,   -- When file will be permanently removed

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_files_owner ON files(owner_id);
CREATE INDEX idx_files_folder ON files(folder_id);
CREATE INDEX idx_files_folder_created ON files(folder_id, created_at DESC)
    WHERE deleted_at IS NULL;  -- Only active files
CREATE INDEX idx_files_blob_hash ON files(blob_hash);
CREATE INDEX idx_files_owner_deleted ON files(owner_id, deleted_at)
    WHERE deleted_at IS NOT NULL;  -- For trash listing
CREATE INDEX idx_files_permanent_deletion ON files(permanent_deletion_at)
    WHERE permanent_deletion_at IS NOT NULL;  -- For cleanup job

-- Trigger
CREATE TRIGGER files_updated_at
    BEFORE UPDATE ON files
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Trigger to update folder item_count
CREATE OR REPLACE FUNCTION update_folder_item_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE folders SET item_count = item_count + 1 WHERE id = NEW.folder_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE folders SET item_count = item_count - 1 WHERE id = OLD.folder_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.folder_id != OLD.folder_id THEN
        UPDATE folders SET item_count = item_count - 1 WHERE id = OLD.folder_id;
        UPDATE folders SET item_count = item_count + 1 WHERE id = NEW.folder_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER files_item_count
    AFTER INSERT OR UPDATE OR DELETE ON files
    FOR EACH ROW EXECUTE FUNCTION update_folder_item_count();

-- Function to soft delete a file
CREATE OR REPLACE FUNCTION soft_delete_file(p_file_id UUID, p_retention_days INTEGER DEFAULT 30)
RETURNS TABLE(deleted_at TIMESTAMPTZ, permanent_deletion_at TIMESTAMPTZ) AS $$
BEGIN
    RETURN QUERY
    UPDATE files
    SET deleted_at = NOW(),
        permanent_deletion_at = NOW() + (p_retention_days || ' days')::INTERVAL,
        updated_at = NOW()
    WHERE id = p_file_id AND files.deleted_at IS NULL
    RETURNING files.deleted_at, files.permanent_deletion_at;
END;
$$ LANGUAGE plpgsql;

-- Function to restore a soft-deleted file
CREATE OR REPLACE FUNCTION restore_file(p_file_id UUID, p_target_folder_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    restored BOOLEAN;
BEGIN
    UPDATE files
    SET deleted_at = NULL,
        permanent_deletion_at = NULL,
        folder_id = p_target_folder_id,
        updated_at = NOW()
    WHERE id = p_file_id
      AND deleted_at IS NOT NULL
      AND permanent_deletion_at > NOW();

    GET DIAGNOSTICS restored = ROW_COUNT;
    RETURN restored > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to permanently delete expired files
CREATE OR REPLACE FUNCTION cleanup_expired_files()
RETURNS TABLE(file_id UUID, blob_storage_key VARCHAR) AS $$
BEGIN
    RETURN QUERY
    DELETE FROM files
    WHERE permanent_deletion_at IS NOT NULL
      AND permanent_deletion_at <= NOW()
    RETURNING id, files.blob_storage_key;
END;
$$ LANGUAGE plpgsql;
```

### 4.7 Share Grants

```sql
CREATE TABLE share_grants (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Resource
    resource_type resource_type NOT NULL,
    resource_id UUID NOT NULL,

    -- Parties
    grantor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    grantee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Cryptographic material
    wrapped_key BYTEA NOT NULL,
    kem_ciphertexts JSONB NOT NULL,

    -- Access control
    permission permission_level NOT NULL DEFAULT 'read',
    recursive BOOLEAN NOT NULL DEFAULT FALSE,
    expiry TIMESTAMPTZ,

    -- Integrity
    signature JSONB NOT NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT share_grants_no_self_share CHECK (grantor_id != grantee_id)
);

-- Indexes
CREATE INDEX idx_share_grants_grantee ON share_grants(grantee_id);
CREATE INDEX idx_share_grants_resource ON share_grants(resource_type, resource_id);
CREATE INDEX idx_share_grants_grantor ON share_grants(grantor_id, created_at DESC);
CREATE INDEX idx_share_grants_expiry ON share_grants(expiry) WHERE expiry IS NOT NULL;

-- Unique constraint: one share per (resource, grantor, grantee)
CREATE UNIQUE INDEX idx_share_grants_unique
    ON share_grants(resource_type, resource_id, grantor_id, grantee_id);
```

### 4.8 Share Links

```sql
CREATE TABLE share_links (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Resource
    resource_type resource_type NOT NULL,
    resource_id UUID NOT NULL,

    -- Creator
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Access token (URL token)
    token CHAR(32) NOT NULL UNIQUE,

    -- Cryptographic material
    wrapped_key BYTEA NOT NULL,

    -- Password protection
    password_protected BOOLEAN NOT NULL DEFAULT FALSE,
    password_salt BYTEA,           -- Salt for Argon2id
    password_hash BYTEA,           -- Hash to verify password

    -- Access control
    permission permission_level NOT NULL DEFAULT 'read',
    expiry TIMESTAMPTZ,
    max_downloads INTEGER,
    download_count INTEGER NOT NULL DEFAULT 0,

    -- Integrity
    signature JSONB NOT NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT share_links_password_check CHECK (
        NOT password_protected OR (password_salt IS NOT NULL AND password_hash IS NOT NULL)
    ),
    CONSTRAINT share_links_max_downloads_check CHECK (
        max_downloads IS NULL OR max_downloads > 0
    )
);

-- Indexes
CREATE INDEX idx_share_links_token ON share_links(token);
CREATE INDEX idx_share_links_creator ON share_links(creator_id, created_at DESC);
CREATE INDEX idx_share_links_resource ON share_links(resource_type, resource_id);
CREATE INDEX idx_share_links_expiry ON share_links(expiry) WHERE expiry IS NOT NULL;

-- Cleanup function for expired/exhausted links
CREATE OR REPLACE FUNCTION cleanup_share_links()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM share_links
    WHERE (expiry IS NOT NULL AND expiry < NOW())
       OR (max_downloads IS NOT NULL AND download_count >= max_downloads);

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

### 4.9 Recovery Shares

```sql
CREATE TABLE recovery_shares (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trustee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Share data
    share_index INTEGER NOT NULL,
    encrypted_share JSONB NOT NULL,

    -- Signatures
    user_signature JSONB NOT NULL,
    trustee_acknowledgment JSONB,

    -- Status
    acknowledged_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id, share_index),
    CHECK(share_index >= 1 AND share_index <= 10)
);

-- Indexes
CREATE INDEX idx_recovery_shares_user ON recovery_shares(user_id);
CREATE INDEX idx_recovery_shares_trustee ON recovery_shares(trustee_id);
```

### 4.10 Recovery Requests

```sql
CREATE TABLE recovery_requests (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Status
    status recovery_status NOT NULL DEFAULT 'pending',
    reason recovery_reason NOT NULL,
    verification_method VARCHAR(128) NOT NULL,

    -- New keys (includes ml_kem, ml_dsa, kaz_kem, kaz_sign)
    -- KEM keys for re-encrypting shares, signing keys for verification
    new_public_keys JSONB NOT NULL,

    -- Progress
    approvals_required INTEGER NOT NULL,
    approvals_received INTEGER NOT NULL DEFAULT 0,

    -- Timing
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_recovery_requests_user ON recovery_requests(user_id, status);
CREATE INDEX idx_recovery_requests_status ON recovery_requests(status, expires_at);
```

### 4.11 Recovery Approvals

```sql
CREATE TABLE recovery_approvals (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    request_id UUID NOT NULL REFERENCES recovery_requests(id) ON DELETE CASCADE,
    trustee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Share data
    share_index INTEGER NOT NULL,
    reencrypted_share JSONB NOT NULL,

    -- Signature
    signature JSONB NOT NULL,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(request_id, trustee_id)
);

-- Indexes
CREATE INDEX idx_recovery_approvals_request ON recovery_approvals(request_id);
```

### 4.12 Audit Events

```sql
CREATE TABLE audit_events (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Context
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Event
    event_type VARCHAR(64) NOT NULL,
    resource_type VARCHAR(32),
    resource_id UUID,

    -- Details
    details JSONB NOT NULL DEFAULT '{}',

    -- Request context
    ip_address INET,
    user_agent VARCHAR(512),

    -- Timestamp
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partitioning by month for large-scale deployments
-- CREATE TABLE audit_events_2025_01 PARTITION OF audit_events
--     FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Indexes
CREATE INDEX idx_audit_events_tenant_time ON audit_events(tenant_id, timestamp DESC);
CREATE INDEX idx_audit_events_user_type ON audit_events(user_id, event_type, timestamp DESC);
CREATE INDEX idx_audit_events_resource ON audit_events(resource_type, resource_id, timestamp DESC);
CREATE INDEX idx_audit_events_type ON audit_events(event_type, timestamp DESC);
```

### 4.13 Devices

```sql
-- Device platform type
CREATE TYPE device_platform AS ENUM ('android', 'ios', 'windows', 'macos', 'linux', 'other');

-- Device status
CREATE TYPE device_status AS ENUM ('active', 'suspended');

-- Device trust level (based on attestation)
CREATE TYPE device_trust_level AS ENUM ('high', 'medium', 'low');

-- Key algorithm for device signing
CREATE TYPE device_key_algorithm AS ENUM ('kaz_sign', 'ml_dsa');

-- Enrollment status
CREATE TYPE enrollment_status AS ENUM ('active', 'revoked');

CREATE TABLE devices (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Device identification
    device_fingerprint VARCHAR(128) NOT NULL,  -- Hash of device characteristics

    -- Platform info
    platform device_platform NOT NULL,
    device_info JSONB NOT NULL DEFAULT '{}',   -- {model, os_version, app_version}

    -- Platform attestation (Phase 2)
    platform_attestation BYTEA,                -- Platform-signed attestation blob
    attestation_verified_at TIMESTAMPTZ,

    -- Status
    status device_status NOT NULL DEFAULT 'active',
    trust_level device_trust_level NOT NULL DEFAULT 'medium',

    -- Timestamps
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_devices_fingerprint ON devices(device_fingerprint);
CREATE INDEX idx_devices_status ON devices(status);

-- Trigger
CREATE TRIGGER devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.14 Device Enrollments

```sql
CREATE TABLE device_enrollments (
    id UUID PRIMARY KEY,  -- App-generated (Ecto/UUIDv7 library)

    -- Relationships
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Cryptographic material
    device_public_key BYTEA NOT NULL,          -- User's device signing key (public)
    key_algorithm device_key_algorithm NOT NULL,

    -- Metadata
    device_name VARCHAR(128),                  -- User-friendly name

    -- Status
    status enrollment_status NOT NULL DEFAULT 'active',
    revoked_at TIMESTAMPTZ,
    revoked_reason VARCHAR(256),

    -- Activity tracking
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,

    -- Timestamps
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(device_id, user_id)  -- One enrollment per user per device
);

-- Indexes
CREATE INDEX idx_device_enrollments_device ON device_enrollments(device_id);
CREATE INDEX idx_device_enrollments_user ON device_enrollments(user_id);
CREATE INDEX idx_device_enrollments_tenant ON device_enrollments(tenant_id);
CREATE INDEX idx_device_enrollments_user_status ON device_enrollments(user_id, status);
CREATE INDEX idx_device_enrollments_device_status ON device_enrollments(device_id, status);

-- Trigger
CREATE TRIGGER device_enrollments_updated_at
    BEFORE UPDATE ON device_enrollments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

## 5. Views

### 5.1 User Storage Usage

```sql
CREATE VIEW user_storage_usage AS
SELECT
    u.id AS user_id,
    u.tenant_id,
    COALESCE(SUM(f.blob_size), 0) AS used_bytes,
    COUNT(f.id) AS file_count
FROM users u
LEFT JOIN files f ON f.owner_id = u.id AND f.deleted_at IS NULL
GROUP BY u.id, u.tenant_id;
```

### 5.2 Tenant Storage Usage

```sql
CREATE VIEW tenant_storage_usage AS
SELECT
    t.id AS tenant_id,
    t.storage_quota_bytes,
    COALESCE(SUM(f.blob_size), 0) AS used_bytes,
    COUNT(DISTINCT u.id) AS user_count,
    COUNT(f.id) AS file_count
FROM tenants t
LEFT JOIN users u ON u.tenant_id = t.id
LEFT JOIN files f ON f.owner_id = u.id AND f.deleted_at IS NULL
GROUP BY t.id;
```

### 5.3 Active Shares

```sql
CREATE VIEW active_shares AS
SELECT
    sg.*,
    CASE WHEN sg.expiry IS NULL OR sg.expiry > NOW() THEN TRUE ELSE FALSE END AS is_active
FROM share_grants sg;
```

## 6. Functions

### 6.1 Get Folder Path

```sql
CREATE OR REPLACE FUNCTION get_folder_path(folder_id UUID)
RETURNS UUID[] AS $$
DECLARE
    path UUID[];
    current_id UUID;
BEGIN
    current_id := folder_id;
    path := ARRAY[]::UUID[];

    WHILE current_id IS NOT NULL LOOP
        path := current_id || path;
        SELECT parent_id INTO current_id FROM folders WHERE id = current_id;
    END LOOP;

    RETURN path;
END;
$$ LANGUAGE plpgsql;
```

### 6.2 Check User Access to Folder

```sql
CREATE OR REPLACE FUNCTION user_can_access_folder(
    p_user_id UUID,
    p_folder_id UUID,
    p_permission permission_level DEFAULT 'read'
)
RETURNS BOOLEAN AS $$
DECLARE
    folder_owner_id UUID;
    folder_path UUID[];
    has_access BOOLEAN;
BEGIN
    -- Check if user is owner
    SELECT owner_id INTO folder_owner_id FROM folders WHERE id = p_folder_id;
    IF folder_owner_id = p_user_id THEN
        RETURN TRUE;
    END IF;

    -- Get folder path
    folder_path := get_folder_path(p_folder_id);

    -- Check for share grant on folder or any ancestor
    SELECT EXISTS (
        SELECT 1 FROM share_grants sg
        WHERE sg.grantee_id = p_user_id
          AND sg.resource_type = 'folder'
          AND sg.resource_id = ANY(folder_path)
          AND (sg.recursive = TRUE OR sg.resource_id = p_folder_id)
          AND sg.permission >= p_permission
          AND (sg.expiry IS NULL OR sg.expiry > NOW())
    ) INTO has_access;

    RETURN has_access;
END;
$$ LANGUAGE plpgsql;
```

## 7. Indexes Summary

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| tenants | idx_tenants_slug | slug | Subdomain lookup |
| users | idx_users_tenant_id | tenant_id | List users in tenant (legacy) |
| users | idx_users_email | email | Email lookup |
| user_tenants | idx_user_tenants_user | user_id | List user's tenants |
| user_tenants | idx_user_tenants_tenant | tenant_id | List tenant's users |
| user_tenants | idx_user_tenants_tenant_role | tenant_id, role | Filter by role |
| credentials | idx_credentials_user | user_id, type | List user's credentials |
| credentials | idx_credentials_credential_id | credential_id | WebAuthn lookup |
| credentials | idx_credentials_external_id | external_id | OIDC lookup |
| folders | idx_folders_owner | owner_id | List user's folders |
| folders | idx_folders_parent | parent_id | Traverse hierarchy |
| files | idx_files_folder | folder_id | List files in folder |
| files | idx_files_folder_created | folder_id, created_at (partial) | Active files in folder |
| files | idx_files_blob_hash | blob_hash | Deduplication |
| files | idx_files_owner_deleted | owner_id, deleted_at (partial) | Trash listing |
| files | idx_files_permanent_deletion | permanent_deletion_at (partial) | Cleanup job |
| share_grants | idx_share_grants_grantee | grantee_id | List received shares |
| share_grants | idx_share_grants_resource | resource_type, resource_id | Find shares for resource |
| share_links | idx_share_links_token | token | URL token lookup |
| share_links | idx_share_links_creator | creator_id, created_at | List user's links |
| share_links | idx_share_links_resource | resource_type, resource_id | Find links for resource |
| audit_events | idx_audit_events_tenant_time | tenant_id, timestamp | Audit queries |

## 8. Migration Notes

### 8.1 Initial Migration

```sql
-- Run in order:
-- 1. Create extensions
-- 2. Create enums
-- 3. Create tables (in FK order)
-- 4. Create indexes
-- 5. Create views
-- 6. Create functions
-- 7. Create triggers
```

### 8.2 Rollback

```sql
-- Drop in reverse order of dependencies
DROP VIEW IF EXISTS active_shares;
DROP VIEW IF EXISTS tenant_storage_usage;
DROP VIEW IF EXISTS user_storage_usage;
DROP TABLE IF EXISTS audit_events CASCADE;
DROP TABLE IF EXISTS recovery_approvals CASCADE;
DROP TABLE IF EXISTS recovery_requests CASCADE;
DROP TABLE IF EXISTS recovery_shares CASCADE;
DROP TABLE IF EXISTS share_links CASCADE;
DROP TABLE IF EXISTS share_grants CASCADE;
DROP TABLE IF EXISTS files CASCADE;
DROP TABLE IF EXISTS folders CASCADE;
DROP TABLE IF EXISTS credentials CASCADE;
DROP TABLE IF EXISTS idp_configs CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS tenants CASCADE;

-- Drop enums
DROP TYPE IF EXISTS credential_type;
DROP TYPE IF EXISTS recovery_reason;
DROP TYPE IF EXISTS recovery_status;
DROP TYPE IF EXISTS permission_level;
DROP TYPE IF EXISTS resource_type;
DROP TYPE IF EXISTS idp_type;
DROP TYPE IF EXISTS user_role;
DROP TYPE IF EXISTS user_status;
DROP TYPE IF EXISTS tenant_plan;
DROP TYPE IF EXISTS tenant_status;
```
