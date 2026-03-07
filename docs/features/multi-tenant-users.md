# Multi-Tenant Users

**Version**: 1.0.0
**Status**: Planned
**Last Updated**: 2026-01-17

## 1. Overview

This document describes the multi-tenant user feature, which allows a single user identity to belong to multiple tenants (organizations). This is essential for enterprise users who work across multiple organizations.

### 1.1 Use Cases

| Scenario | Description |
|----------|-------------|
| Consultants | Work with multiple client companies |
| Contractors | Freelancers serving several organizations |
| Agencies | Staff accessing client workspaces |
| Board Members | Serve on multiple company boards |
| M&A Transitions | Employees during company mergers |

### 1.2 Design Principles

1. **Single Identity**: User has one set of cryptographic keys across all tenants
2. **Per-Tenant Access**: Folder KEKs are wrapped for user's keys per tenant
3. **Tenant Isolation**: Data from Tenant A is never visible to Tenant B admins
4. **Role Per Tenant**: User can be `admin` in one tenant and `member` in another

## 2. Architecture

### 2.1 Current vs. Proposed Model

```
CURRENT: One-to-Many (User belongs to ONE tenant)
┌─────────┐     ┌──────────┐
│ Tenant  │────<│   User   │
└─────────┘     └──────────┘
                 tenant_id (NOT NULL)

PROPOSED: Many-to-Many (User can belong to MANY tenants)
┌─────────┐     ┌──────────────┐     ┌──────────┐
│ Tenant  │────<│ UserTenant   │>────│   User   │
└─────────┘     └──────────────┘     └──────────┘
                 - role
                 - joined_at
                 - invited_by
```

### 2.2 Key Hierarchy (Multi-Tenant)

```
User Identity (single key bundle)
│
├── KAZ-KEM Key Pair ──────────────────────┐
├── ML-KEM Key Pair                        │
├── KAZ-SIGN Key Pair                      │ Shared across
├── ML-DSA Key Pair                        │ all tenants
├── Encrypted Private Keys                 │
└── Master Key (MK)  ──────────────────────┘
    │
    ├── Tenant A
    │   └── Root Folder
    │       └── owner_key_access: { wrapped for user's KEM keys }
    │
    ├── Tenant B
    │   └── Root Folder
    │       └── owner_key_access: { wrapped for user's KEM keys }
    │
    └── Tenant C
        └── Root Folder
            └── owner_key_access: { wrapped for user's KEM keys }
```

**Security Model**: Each tenant's folder KEK is independently wrapped for the user's public keys. User's single key bundle can decrypt any tenant's resources they have access to.

## 3. Database Schema Changes

### 3.1 New Table: `user_tenants`

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

-- Trigger for updated_at
CREATE TRIGGER user_tenants_updated_at
    BEFORE UPDATE ON user_tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 3.2 Modify Table: `users`

```sql
-- Remove tenant_id from users table (nullable during migration, then dropped)
ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL;

-- Remove role from users (now in user_tenants)
-- Note: Migration should copy role to user_tenants first
ALTER TABLE users DROP COLUMN role;

-- Remove the unique constraint on (tenant_id, email)
ALTER TABLE users DROP CONSTRAINT users_tenant_id_email_key;

-- Add global email uniqueness (optional - depends on policy)
-- Option A: Email globally unique
ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE(email);

-- Option B: Email unique within tenant (enforced at user_tenants level)
-- CREATE UNIQUE INDEX idx_user_tenants_email_tenant
--     ON user_tenants(tenant_id, (SELECT email FROM users WHERE id = user_id));
```

### 3.3 Migration Steps

```elixir
# Migration: Add multi-tenant user support

def change do
  # 1. Create user_tenants junction table
  create table(:user_tenants, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
    add :role, :string, null: false, default: "member"
    add :invited_by, references(:users, type: :binary_id, on_delete: :nilify_all)
    add :invitation_accepted_at, :utc_datetime_usec
    add :status, :string, null: false, default: "active"
    add :joined_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    timestamps(type: :utc_datetime_usec)
  end

  create unique_index(:user_tenants, [:user_id, :tenant_id])
  create index(:user_tenants, [:user_id])
  create index(:user_tenants, [:tenant_id])
  create index(:user_tenants, [:tenant_id, :role])

  # 2. Migrate existing user-tenant relationships
  execute """
    INSERT INTO user_tenants (id, user_id, tenant_id, role, joined_at, created_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      tenant_id,
      role,
      created_at,
      NOW(),
      NOW()
    FROM users
    WHERE tenant_id IS NOT NULL
  """, ""

  # 3. Make tenant_id nullable (keep for backwards compatibility during transition)
  alter table(:users) do
    modify :tenant_id, :binary_id, null: true
  end

  # 4. Remove role from users (now in user_tenants)
  alter table(:users) do
    remove :role
  end
end
```

## 4. Application Layer Changes

### 4.1 Ecto Schemas

#### User Schema (Updated)

```elixir
defmodule SecureSharing.Accounts.User do
  use Ecto.Schema

  schema "users" do
    # Remove: belongs_to :tenant, SecureSharing.Accounts.Tenant
    # Remove: field :role, Ecto.Enum

    # Add many-to-many relationship
    has_many :user_tenants, SecureSharing.Accounts.UserTenant
    has_many :tenants, through: [:user_tenants, :tenant]

    # ... rest of fields unchanged
  end
end
```

#### New UserTenant Schema

```elixir
defmodule SecureSharing.Accounts.UserTenant do
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_tenants" do
    belongs_to :user, SecureSharing.Accounts.User
    belongs_to :tenant, SecureSharing.Accounts.Tenant
    belongs_to :invited_by, SecureSharing.Accounts.User

    field :role, Ecto.Enum, values: [:member, :admin, :owner], default: :member
    field :status, :string, default: "active"
    field :invitation_accepted_at, :utc_datetime_usec
    field :joined_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
```

#### Tenant Schema (Updated)

```elixir
defmodule SecureSharing.Accounts.Tenant do
  use Ecto.Schema

  schema "tenants" do
    # Update relationship
    has_many :user_tenants, SecureSharing.Accounts.UserTenant
    has_many :users, through: [:user_tenants, :user]

    # ... rest unchanged
  end
end
```

### 4.2 Authentication Flow

#### Login Response (Updated)

```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "user": {
    "id": "user-uuid",
    "email": "user@example.com",
    "tenants": [
      {
        "id": "tenant-1-uuid",
        "name": "Acme Corp",
        "slug": "acme",
        "role": "admin"
      },
      {
        "id": "tenant-2-uuid",
        "name": "Consulting Inc",
        "slug": "consulting",
        "role": "member"
      }
    ],
    "default_tenant_id": "tenant-1-uuid"
  }
}
```

#### JWT Claims (Updated)

```json
{
  "sub": "user-uuid",
  "tid": "tenant-uuid",  // Currently selected tenant
  "role": "admin",       // Role in current tenant
  "exp": 1234567890
}
```

### 4.3 Tenant Context Management

#### Setting Tenant Context

```elixir
# In Authenticate plug
defp load_tenant_from_claims(conn, claims) do
  tenant_id = claims["tid"]
  user_id = claims["sub"]

  # Verify user belongs to this tenant
  case Accounts.get_user_tenant(user_id, tenant_id) do
    nil ->
      {:error, :unauthorized}
    user_tenant ->
      tenant = Accounts.get_tenant!(tenant_id)
      conn
      |> assign(:current_tenant, tenant)
      |> assign(:current_role, user_tenant.role)
  end
end
```

#### Switching Tenants

```elixir
# POST /api/tenant/switch
def switch_tenant(conn, %{"tenant_id" => tenant_id}) do
  user = conn.assigns[:current_user]

  case Accounts.get_user_tenant(user.id, tenant_id) do
    nil ->
      {:error, :forbidden}
    user_tenant ->
      # Generate new tokens with updated tenant context
      {:ok, tokens} = Token.generate_tokens(user, tenant_id, user_tenant.role)
      json(conn, tokens)
  end
end
```

### 4.4 New API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/tenants` | List user's tenants |
| POST | `/api/tenant/switch` | Switch active tenant |
| POST | `/api/tenants/:id/invite` | Invite user to tenant (admin) |
| POST | `/api/tenants/:id/join` | Accept invitation |
| DELETE | `/api/tenants/:id/leave` | Leave tenant |
| PUT | `/api/tenants/:id/users/:user_id/role` | Update user's role (admin) |
| DELETE | `/api/tenants/:id/users/:user_id` | Remove user from tenant (admin) |

## 5. Android Client Changes

### 5.1 UI Changes

#### Tenant Switcher

Add a tenant switcher in the app header/drawer:

```kotlin
@Composable
fun TenantSwitcher(
    currentTenant: Tenant,
    availableTenants: List<Tenant>,
    onTenantSelected: (Tenant) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false }
    ) {
        availableTenants.forEach { tenant ->
            DropdownMenuItem(
                text = {
                    Row {
                        Text(tenant.name)
                        if (tenant.id == currentTenant.id) {
                            Icon(Icons.Default.Check, "Current")
                        }
                    }
                },
                onClick = {
                    onTenantSelected(tenant)
                    expanded = false
                }
            )
        }
    }
}
```

### 5.2 State Management

```kotlin
// TenantManager.kt
@Singleton
class TenantManager @Inject constructor(
    private val secureStorage: SecureStorage,
    private val apiService: ApiService
) {
    private val _currentTenant = MutableStateFlow<Tenant?>(null)
    val currentTenant: StateFlow<Tenant?> = _currentTenant.asStateFlow()

    private val _availableTenants = MutableStateFlow<List<Tenant>>(emptyList())
    val availableTenants: StateFlow<List<Tenant>> = _availableTenants.asStateFlow()

    suspend fun switchTenant(tenantId: String): Result<Unit> {
        return when (val result = apiService.switchTenant(tenantId)) {
            is Result.Success -> {
                secureStorage.saveTokens(result.data)
                _currentTenant.value = availableTenants.value.find { it.id == tenantId }
                Result.Success(Unit)
            }
            is Result.Error -> result
        }
    }

    fun setTenants(tenants: List<Tenant>, currentId: String) {
        _availableTenants.value = tenants
        _currentTenant.value = tenants.find { it.id == currentId }
    }
}
```

### 5.3 Login Flow Update

```kotlin
// After successful login
fun handleLoginSuccess(response: LoginResponse) {
    // Store tokens
    secureStorage.saveTokens(response.accessToken, response.refreshToken)

    // Set available tenants
    tenantManager.setTenants(
        tenants = response.user.tenants,
        currentId = response.user.defaultTenantId
    )

    // Navigate to file browser
    navigateToHome()
}
```

## 6. Security Considerations

### 6.1 Tenant Isolation

- User's keys are shared, but folder KEKs are per-tenant
- Tenant A admin cannot see user's activity in Tenant B
- Audit logs are per-tenant

### 6.2 Key Recovery

- Recovery trustees can be from any tenant
- Recommendation: Choose trustees from your primary organization
- Recovery restores access to ALL tenants (same key bundle)

### 6.3 Revoking Access

When removing user from tenant:
1. Delete `user_tenants` record
2. User can no longer switch to that tenant
3. User's cached folder KEKs for that tenant should be cleared on client
4. Optionally: Re-wrap shared folder KEKs without this user

## 7. Migration Path

### Phase 1: Database Migration
1. Create `user_tenants` table
2. Copy existing user-tenant-role relationships
3. Make `users.tenant_id` nullable
4. Deploy backend with dual-write

### Phase 2: Backend Updates
1. Update authentication to use `user_tenants`
2. Add tenant switching endpoints
3. Update all tenant-scoped queries

### Phase 3: Client Updates
1. Update login response handling
2. Add tenant switcher UI
3. Update API calls to include tenant context

### Phase 4: Cleanup
1. Remove `users.tenant_id` column
2. Remove `users.role` column
3. Update documentation

## 8. Testing Checklist

- [ ] User can log in and see multiple tenants
- [ ] User can switch between tenants
- [ ] Files from Tenant A not visible when viewing Tenant B
- [ ] User role is correct per tenant
- [ ] Admin in Tenant A cannot see users' activity in Tenant B
- [ ] Leaving a tenant removes access
- [ ] Re-joining a tenant works
- [ ] Key recovery restores access to all tenants
