# SecureSharing Elixir/OTP Development Plan

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

This document outlines the development plan for SecureSharing's backend using Elixir/OTP and the Phoenix framework. The plan emphasizes:

- **Test-Driven Development (TDD)**: Tests written before implementation
- **OTP Design Patterns**: Leveraging Erlang/OTP's battle-tested patterns
- **Behaviour-Based Abstractions**: Clean interfaces for pluggable components
- **Incremental Delivery**: Each phase produces working, tested software

## 2. Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Language | Elixir 1.16+ | Primary backend language |
| Runtime | Erlang/OTP 26+ | BEAM VM for fault tolerance |
| Framework | Phoenix 1.7+ | Web framework |
| Database | PostgreSQL 18+ | Primary data store (UUIDv7 support) |
| ORM | Ecto 3.11+ | Database interactions |
| Background Jobs | Oban 2.17+ | Reliable job processing |
| Testing | ExUnit + StreamData | Unit, integration, property tests |
| Mocking | Mox | Behaviour-based mocking |
| Crypto | Rust NIFs | PQC and symmetric operations |
| Blob Storage | Local FS / S3 | File blob storage (local dev, S3 prod) |
| Real-time | Phoenix Channels | WebSocket connections |
| Auth (MVP) | Email/Password | Built-in Phoenix auth (`phx.gen.auth`) |
| Auth (Future) | Passkeys, OIDC | Progressive enhancement |

### Authentication Strategy

**MVP**: Email + Password
- Simple to implement with `mix phx.gen.auth`
- Password directly derives Master Key via Argon2id → HKDF
- Full zero-knowledge from day one
- No external dependencies

**Phase 2**: Add Passkeys (WebAuthn)
- Modern, phishing-resistant
- PRF extension provides key material for MK derivation
- Best user experience

**Phase 3**: Enterprise OIDC/SAML (Optional)
- For organizations requiring SSO
- Requires "vault password" for encryption (OIDC doesn't provide key material)
- Keycloak (self-hosted) or Auth0 (SaaS)

## 3. Project Structure

```
secure_sharing/
├── lib/
│   ├── secure_sharing/                    # Business Logic (Contexts)
│   │   ├── application.ex                 # OTP Application
│   │   ├── repo.ex                        # Ecto Repo
│   │   │
│   │   ├── accounts/                      # Accounts Context
│   │   │   ├── accounts.ex                # Public API
│   │   │   ├── user.ex                    # User schema
│   │   │   ├── credential.ex              # Credential schema
│   │   │   ├── tenant.ex                  # Tenant schema
│   │   │   └── queries/                   # Complex queries
│   │   │
│   │   ├── vault/                         # Vault Context (Keys)
│   │   │   ├── vault.ex                   # Public API
│   │   │   ├── key_bundle.ex              # User key bundle
│   │   │   └── recovery_share.ex          # Shamir shares
│   │   │
│   │   ├── storage/                       # Storage Context
│   │   │   ├── storage.ex                 # Public API
│   │   │   ├── file.ex                    # File schema
│   │   │   ├── folder.ex                  # Folder schema
│   │   │   ├── blob_store.ex              # S3 abstraction
│   │   │   └── upload_coordinator.ex      # GenServer for uploads
│   │   │
│   │   ├── sharing/                       # Sharing Context
│   │   │   ├── sharing.ex                 # Public API
│   │   │   ├── share_grant.ex             # User-to-user shares
│   │   │   ├── share_link.ex              # Anonymous links
│   │   │   └── permission.ex              # Permission logic
│   │   │
│   │   ├── recovery/                      # Recovery Context
│   │   │   ├── recovery.ex                # Public API
│   │   │   ├── recovery_request.ex        # Recovery request schema
│   │   │   ├── recovery_approval.ex       # Trustee approvals
│   │   │   └── shamir_coordinator.ex      # Reconstruction logic
│   │   │
│   │   ├── identity/                      # Identity Context
│   │   │   ├── identity.ex                # Public API
│   │   │   ├── idp_config.ex              # IdP configuration
│   │   │   ├── providers/                 # IdP implementations
│   │   │   │   ├── provider.ex            # Behaviour definition
│   │   │   │   ├── password.ex            # Email/Password (MVP)
│   │   │   │   ├── webauthn.ex            # WebAuthn adapter (Future)
│   │   │   │   └── oidc.ex                # OIDC adapter (Future)
│   │   │   └── session.ex                 # Session management
│   │   │
│   │   ├── crypto/                        # Crypto Context (NIF wrapper)
│   │   │   ├── crypto.ex                  # Public API
│   │   │   ├── native.ex                  # Rustler NIF bindings
│   │   │   ├── signature.ex               # Signature verification
│   │   │   └── key_wrap.ex                # Key wrap operations
│   │   │
│   │   ├── audit/                         # Audit Context
│   │   │   ├── audit.ex                   # Public API
│   │   │   └── event.ex                   # Audit event schema
│   │   │
│   │   └── workers/                       # Oban Workers
│   │       ├── cleanup_worker.ex          # Expired data cleanup
│   │       ├── notification_worker.ex     # Notifications
│   │       └── quota_worker.ex            # Quota calculations
│   │
│   ├── secure_sharing_web/                # Web Layer
│   │   ├── endpoint.ex                    # Phoenix Endpoint
│   │   ├── router.ex                      # API Routes
│   │   ├── telemetry.ex                   # Metrics
│   │   │
│   │   ├── controllers/                   # REST Controllers
│   │   │   ├── auth_controller.ex
│   │   │   ├── user_controller.ex
│   │   │   ├── file_controller.ex
│   │   │   ├── folder_controller.ex
│   │   │   ├── share_controller.ex
│   │   │   └── recovery_controller.ex
│   │   │
│   │   ├── channels/                      # WebSocket Channels
│   │   │   ├── user_socket.ex
│   │   │   ├── folder_channel.ex          # Real-time folder updates
│   │   │   └── presence.ex                # User presence
│   │   │
│   │   ├── live/                          # LiveView (Admin Portal)
│   │   │   ├── admin/
│   │   │   │   ├── dashboard_live.ex
│   │   │   │   ├── tenant_live.ex
│   │   │   │   └── user_live.ex
│   │   │   └── components/
│   │   │
│   │   ├── plugs/                         # Custom Plugs
│   │   │   ├── authenticate.ex            # JWT verification
│   │   │   ├── tenant_context.ex          # Multi-tenancy
│   │   │   ├── rate_limit.ex              # Rate limiting
│   │   │   └── signature_verify.ex        # Request signature
│   │   │
│   │   └── views/                         # JSON Views
│   │       ├── error_view.ex
│   │       └── api/
│
├── native/                                 # Rust NIFs (standard Rustler location)
│   └── secure_sharing_crypto/
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs                     # Rustler NIF entry point
│           ├── ml_kem.rs
│           ├── ml_dsa.rs
│           ├── kaz_kem.rs
│           ├── kaz_sign.rs
│           └── aes_gcm.rs
│
├── test/
│   ├── support/
│   │   ├── factory.ex                     # ExMachina factories
│   │   ├── fixtures.ex                    # Test fixtures
│   │   └── conn_case.ex                   # Controller test case
│   │
│   ├── secure_sharing/                    # Context tests
│   │   ├── accounts_test.exs
│   │   ├── storage_test.exs
│   │   ├── sharing_test.exs
│   │   └── crypto_test.exs
│   │
│   ├── secure_sharing_web/                # Web tests
│   │   ├── controllers/
│   │   └── channels/
│   │
│   └── integration/                       # End-to-end tests
│       ├── upload_flow_test.exs
│       ├── share_flow_test.exs
│       └── recovery_flow_test.exs
│
├── priv/
│   └── repo/migrations/                   # Ecto migrations
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
│
└── mix.exs
```

## 4. Design Patterns & Best Practices

### 4.1 Phoenix Contexts (Domain-Driven Design)

Each context encapsulates a bounded domain with a clear public API:

```elixir
defmodule SecureSharing.Storage do
  @moduledoc """
  The Storage context handles files and folders.

  ## Public API

  - `create_file/2` - Create file metadata
  - `get_file/2` - Retrieve file with access check
  - `list_folder_contents/2` - List folder children
  """

  alias SecureSharing.Storage.{File, Folder}
  alias SecureSharing.Repo

  # Public API functions only
  # Implementation details hidden in submodules
end
```

**Rules:**
- Contexts don't call each other's internal modules
- Cross-context communication via public APIs only
- Each context owns its schemas

### 4.2 Behaviours (Interface Abstraction)

Use behaviours for pluggable components:

```elixir
defmodule SecureSharing.Identity.Provider do
  @moduledoc """
  Behaviour for identity providers.
  """

  @type auth_result :: {:ok, map()} | {:error, atom()}

  @callback initiate_auth(config :: map()) :: {:ok, redirect_url :: String.t()}
  @callback validate_callback(params :: map()) :: auth_result()
  @callback get_user_info(token :: String.t()) :: {:ok, map()}
  @callback provides_key_material?() :: boolean()
end

defmodule SecureSharing.Identity.Providers.OIDC do
  @behaviour SecureSharing.Identity.Provider

  @impl true
  def initiate_auth(config) do
    # OIDC implementation
  end

  @impl true
  def provides_key_material?, do: false
end
```

**Used For:**
- Identity providers (WebAuthn, OIDC, Digital ID)
- Blob storage backends (S3, MinIO, local)
- Notification channels (email, push)

### 4.3 GenServer (Stateful Processes)

Use GenServers for coordinating stateful operations:

```elixir
defmodule SecureSharing.Storage.UploadCoordinator do
  @moduledoc """
  Coordinates chunked uploads.

  Holds upload state in memory, persists on completion/failure.
  """
  use GenServer

  defstruct [:upload_id, :chunks, :status, :started_at]

  # Client API
  def start_upload(file_id, total_chunks) do
    GenServer.call(__MODULE__, {:start, file_id, total_chunks})
  end

  def receive_chunk(upload_id, chunk_index, data) do
    GenServer.call(__MODULE__, {:chunk, upload_id, chunk_index, data})
  end

  # Server Callbacks
  @impl true
  def init(_opts) do
    {:ok, %{uploads: %{}}}
  end

  @impl true
  def handle_call({:start, file_id, total_chunks}, _from, state) do
    # Implementation
  end
end
```

**Used For:**
- Chunked file uploads
- Rate limiting per user
- Session state
- Presence tracking

### 4.4 Supervision Trees (Fault Tolerance)

Design supervision trees for isolation and recovery:

```elixir
defmodule SecureSharing.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Database
      SecureSharing.Repo,

      # PubSub for real-time
      {Phoenix.PubSub, name: SecureSharing.PubSub},

      # Background jobs
      {Oban, Application.fetch_env!(:secure_sharing, Oban)},

      # Upload coordinators (one per upload)
      {DynamicSupervisor, name: SecureSharing.UploadSupervisor, strategy: :one_for_one},

      # Rate limiters (one per tenant)
      {Registry, keys: :unique, name: SecureSharing.RateLimiterRegistry},
      {DynamicSupervisor, name: SecureSharing.RateLimiterSupervisor},

      # Presence tracking
      SecureSharingWeb.Presence,

      # Web endpoint (must be last)
      SecureSharingWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SecureSharing.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Supervision Strategy:**
- `:one_for_one` - Restart only crashed child
- `:rest_for_one` - Restart crashed child and those started after it
- `:one_for_all` - Restart all children if one crashes

### 4.5 ETS (In-Memory Cache)

Use ETS for high-performance caching:

```elixir
defmodule SecureSharing.Cache do
  @moduledoc """
  In-memory cache using ETS.
  """

  @table :secure_sharing_cache

  def init do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > System.system_time(:second) ->
        {:ok, value}
      _ ->
        :miss
    end
  end

  def put(key, value, ttl_seconds) do
    expires_at = System.system_time(:second) + ttl_seconds
    :ets.insert(@table, {key, value, expires_at})
    :ok
  end
end
```

**Used For:**
- Public key caching (avoid DB lookups for signature verification)
- Rate limit counters
- Session data

### 4.6 Broadway (Data Pipelines)

Use Broadway for processing file operations at scale:

```elixir
defmodule SecureSharing.Storage.BlobProcessor do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "blob_processing"}
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        s3: [concurrency: 5, batch_size: 10]
      ]
    )
  end

  @impl true
  def handle_message(_, message, _) do
    # Process individual blob
    message
  end

  @impl true
  def handle_batch(:s3, messages, _, _) do
    # Batch upload to S3
    messages
  end
end
```

### 4.7 Rust NIFs (Native Performance)

Integrate Rust for cryptographic operations:

```elixir
defmodule SecureSharing.Crypto.Native do
  use Rustler, otp_app: :secure_sharing_crypto, crate: "secure_sharing_crypto"

  # NIFs - will be replaced by Rust implementations
  def ml_kem_encapsulate(_public_key), do: :erlang.nif_error(:nif_not_loaded)
  def ml_kem_decapsulate(_private_key, _ciphertext), do: :erlang.nif_error(:nif_not_loaded)
  def ml_dsa_sign(_private_key, _message), do: :erlang.nif_error(:nif_not_loaded)
  def ml_dsa_verify(_public_key, _message, _signature), do: :erlang.nif_error(:nif_not_loaded)
  def aes_gcm_encrypt(_key, _nonce, _plaintext, _aad), do: :erlang.nif_error(:nif_not_loaded)
  def aes_gcm_decrypt(_key, _nonce, _ciphertext, _aad), do: :erlang.nif_error(:nif_not_loaded)
end
```

Corresponding Rust:

```rust
// native/src/lib.rs
use rustler::{Encoder, Env, NifResult, Term};

#[rustler::nif]
fn ml_dsa_verify(
    public_key: Binary,
    message: Binary,
    signature: Binary,
) -> NifResult<bool> {
    // Use pqcrypto or liboqs
    let pk = ml_dsa::PublicKey::from_bytes(&public_key)?;
    let sig = ml_dsa::Signature::from_bytes(&signature)?;
    Ok(pk.verify(&message, &sig).is_ok())
}

rustler::init!("Elixir.SecureSharing.Crypto.Native", [
    ml_kem_encapsulate,
    ml_kem_decapsulate,
    ml_dsa_sign,
    ml_dsa_verify,
    aes_gcm_encrypt,
    aes_gcm_decrypt,
]);
```

---

## 5. Test-Driven Development Approach

### 5.1 TDD Cycle

For every feature:

```
┌─────────────────────────────────────────────────────────────────┐
│                         TDD CYCLE                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│      ┌─────────┐                                                │
│      │  RED    │  1. Write failing test                         │
│      │         │     - Define expected behavior                 │
│      │         │     - Run test, confirm failure                │
│      └────┬────┘                                                │
│           │                                                     │
│           ▼                                                     │
│      ┌─────────┐                                                │
│      │  GREEN  │  2. Write minimal implementation               │
│      │         │     - Just enough to pass                      │
│      │         │     - No premature optimization                │
│      └────┬────┘                                                │
│           │                                                     │
│           ▼                                                     │
│      ┌─────────┐                                                │
│      │REFACTOR │  3. Clean up                                   │
│      │         │     - Improve design                           │
│      │         │     - Keep tests passing                       │
│      └────┬────┘                                                │
│           │                                                     │
│           └──────────────────────────────────────▶ Repeat       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Test Types

| Type | Location | Purpose | Speed |
|------|----------|---------|-------|
| Unit | `test/<context>_test.exs` | Test individual functions | Fast |
| Integration | `test/integration/` | Test context interactions | Medium |
| Controller | `test/web/controllers/` | Test HTTP endpoints | Medium |
| Channel | `test/web/channels/` | Test WebSocket | Medium |
| Property | Embedded with `StreamData` | Generative testing | Slow |
| End-to-End | `test/e2e/` | Full flow tests | Slow |

### 5.3 Test Structure

```elixir
defmodule SecureSharing.StorageTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Storage
  alias SecureSharing.AccountsFixtures

  describe "create_file/2" do
    setup do
      user = AccountsFixtures.user_fixture()
      folder = StorageFixtures.folder_fixture(owner: user)
      {:ok, user: user, folder: folder}
    end

    test "creates file with valid attributes", %{user: user, folder: folder} do
      attrs = %{
        encrypted_metadata: <<1, 2, 3>>,
        metadata_nonce: <<4, 5, 6>>,
        wrapped_dek: <<7, 8, 9>>,
        blob_size: 1024,
        blob_hash: "abc123",
        signature: %{ml_dsa: <<>>, kaz_sign: <<>>}
      }

      assert {:ok, file} = Storage.create_file(folder, attrs)
      assert file.owner_id == user.id
      assert file.folder_id == folder.id
      assert file.blob_size == 1024
    end

    test "fails without required fields", %{folder: folder} do
      assert {:error, changeset} = Storage.create_file(folder, %{})
      assert "can't be blank" in errors_on(changeset).encrypted_metadata
    end
  end
end
```

### 5.4 Mocking with Mox

Define mocks for behaviours:

```elixir
# test/support/mocks.ex
Mox.defmock(SecureSharing.Identity.ProviderMock,
  for: SecureSharing.Identity.Provider
)

Mox.defmock(SecureSharing.Storage.BlobStoreMock,
  for: SecureSharing.Storage.BlobStore
)

# test/secure_sharing/identity_test.exs
defmodule SecureSharing.IdentityTest do
  use SecureSharing.DataCase, async: true
  import Mox

  setup :verify_on_exit!

  describe "authenticate/2 with OIDC" do
    test "creates user on first login" do
      SecureSharing.Identity.ProviderMock
      |> expect(:validate_callback, fn _params ->
        {:ok, %{sub: "user123", email: "test@example.com"}}
      end)
      |> expect(:provides_key_material?, fn -> false end)

      assert {:ok, user} = Identity.authenticate(:oidc, %{code: "abc"})
      assert user.email == "test@example.com"
    end
  end
end
```

### 5.5 Property-Based Testing

Use StreamData for generative tests:

```elixir
defmodule SecureSharing.Crypto.SignaturePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SecureSharing.Crypto

  property "sign then verify always succeeds" do
    check all message <- binary(min_length: 1, max_length: 10_000),
              max_runs: 100 do
      {:ok, keypair} = Crypto.generate_signing_keypair()
      {:ok, signature} = Crypto.sign(keypair.private_key, message)

      assert {:ok, true} = Crypto.verify(keypair.public_key, message, signature)
    end
  end

  property "verify fails with wrong message" do
    check all message <- binary(min_length: 1),
              wrong_message <- binary(min_length: 1),
              message != wrong_message do
      {:ok, keypair} = Crypto.generate_signing_keypair()
      {:ok, signature} = Crypto.sign(keypair.private_key, message)

      assert {:ok, false} = Crypto.verify(keypair.public_key, wrong_message, signature)
    end
  end
end
```

---

## 6. Development Phases

### Phase 1: Project Foundation

**Duration Estimate**: Foundation phase

**Goals:**
- Set up Elixir/Phoenix project structure
- Configure development environment
- Establish testing infrastructure
- Create base schemas and migrations

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Phoenix project | Base project with dependencies | `mix phx.server` runs |
| Database setup | PostgreSQL with migrations | All enums and base tables created |
| Test infrastructure | ExUnit, Mox, factories | `mix test` passes with sample tests |
| CI pipeline | GitHub Actions | Tests run on PR |
| Dev environment | Docker Compose | `docker-compose up` starts all services |

**Key Dependencies for Phase 1:**
```elixir
# Add to mix.exs deps
{:uuidv7, "~> 1.0"},  # Provides UUIDv7 Ecto type for @primary_key
```

**Technical Features:**
- **UUIDv7 primary keys** via `uuidv7` library (app-generated, time-ordered)
  - Library provides the `UUIDv7` Ecto type used in `@primary_key {:id, UUIDv7, autogenerate: true}`
  - No custom type module needed - the library handles Ecto integration
- **Canonical timestamps** matching `02-database-schema.md`:
  - Column naming: `created_at`/`updated_at` (not Ecto's default `inserted_at`)
  - Type: `TIMESTAMPTZ` (timestamp with timezone)
  - DB defaults: `DEFAULT NOW()`
  - Auto-update triggers: `update_updated_at()` function
- **Base schema module** (`SecureSharing.Schema`) for consistent configuration
- Ecto schemas with embedded schemas for JSONB
- Custom Ecto types for binary data
- Database migrations matching `02-database-schema.md`
- Mix aliases for common tasks

**UUIDv7 and Timestamp Configuration:**

```elixir
# lib/secure_sharing/repo.ex
defmodule SecureSharing.Repo do
  use Ecto.Repo,
    otp_app: :secure_sharing,
    adapter: Ecto.Adapters.Postgres

  # App-generated UUIDv7 for all primary keys (via uuidv7 library)
  @impl true
  def default_options(_operation) do
    [returning: true]
  end
end

# First migration: Create the update_updated_at() trigger function
defmodule SecureSharing.Repo.Migrations.CreateTimestampFunction do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION update_updated_at()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS update_updated_at()"
  end
end

# Example table migration using canonical timestamps
defmodule SecureSharing.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      # UUIDv7 primary key (app-generated via uuidv7 library)
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :email, :string, null: false
      # ... other fields

      # Canonical timestamps: TIMESTAMPTZ with DB defaults
      add :created_at, :timestamptz, null: false, default: fragment("NOW()")
      add :updated_at, :timestamptz, null: false, default: fragment("NOW()")
    end

    # Auto-update trigger for updated_at
    execute(
      "CREATE TRIGGER users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at()",
      "DROP TRIGGER IF EXISTS users_updated_at ON users"
    )
  end
end

# Base schema module (lib/secure_sharing/schema.ex)
#
# Requires: {:uuidv7, "~> 1.0"} in mix.exs - provides the UUIDv7 Ecto type
#
# Configures Ecto to work with:
# - UUIDv7 primary keys (time-ordered, app-generated via uuidv7 library)
# - Canonical timestamp columns (created_at/updated_at with TIMESTAMPTZ)
# - DB handles defaults (NOW()) and triggers (update_updated_at)
defmodule SecureSharing.Schema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      # UUIDv7 type is provided by the uuidv7 library (not a custom module)
      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type UUIDv7
      @timestamps_opts [
        inserted_at: :created_at,  # Use created_at column (not Ecto's default inserted_at)
        type: :utc_datetime_usec   # Maps to TIMESTAMPTZ in PostgreSQL
      ]
    end
  end
end

# Example schema using base module
defmodule SecureSharing.Accounts.User do
  use SecureSharing.Schema  # Provides UUIDv7 PKs and canonical timestamp config

  schema "users" do
    field :email, :string
    belongs_to :tenant, SecureSharing.Accounts.Tenant

    timestamps()  # Uses created_at/updated_at columns (configured via @timestamps_opts)
  end
end
```

**TDD Approach:**

```elixir
# Write tests FIRST for each schema

# test/secure_sharing/accounts/tenant_test.exs
defmodule SecureSharing.Accounts.TenantTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts.Tenant

  describe "changeset/2" do
    test "valid with required fields" do
      attrs = %{name: "Acme Corp", slug: "acme-corp"}
      changeset = Tenant.changeset(%Tenant{}, attrs)
      assert changeset.valid?
    end

    test "slug must be unique" do
      insert(:tenant, slug: "taken-slug")
      attrs = %{name: "Another", slug: "taken-slug"}

      {:error, changeset} =
        %Tenant{}
        |> Tenant.changeset(attrs)
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "status must be valid enum" do
      attrs = %{name: "Test", slug: "test", status: :active}
      changeset = Tenant.changeset(%Tenant{}, attrs)
      assert changeset.valid?
    end
  end
end

# test/secure_sharing/accounts/user_test.exs
defmodule SecureSharing.Accounts.UserTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts.User

  describe "registration_changeset/2" do
    test "valid with required fields" do
      tenant = insert(:tenant)
      attrs = %{
        tenant_id: tenant.id,
        email: "test@example.com",
        password: "secure_password123"
      }

      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "email must be unique within tenant" do
      user = insert(:user)

      {:error, changeset} =
        %User{}
        |> User.registration_changeset(%{
          tenant_id: user.tenant_id,
          email: user.email,
          password: "password123456"
        })
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "role_changeset/2" do
    test "valid role values" do
      user = insert(:user)
      for role <- [:member, :admin, :owner] do
        changeset = User.role_changeset(user, %{role: role})
        assert changeset.valid?
      end
    end
  end
end

# test/secure_sharing/accounts/idp_config_test.exs
defmodule SecureSharing.Accounts.IdpConfigTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts.IdpConfig

  describe "changeset/2" do
    test "valid WebAuthn config" do
      tenant = insert(:tenant)
      attrs = %{
        tenant_id: tenant.id,
        type: :webauthn,
        name: "Passkeys",
        provides_key_material: true,
        config: %{"rp_id" => "example.com", "rp_name" => "Example"}
      }

      changeset = IdpConfig.changeset(%IdpConfig{}, attrs)
      assert changeset.valid?
    end

    test "validates required config fields for OIDC" do
      tenant = insert(:tenant)
      attrs = %{
        tenant_id: tenant.id,
        type: :oidc,
        name: "Google",
        config: %{}  # Missing required fields
      }

      changeset = IdpConfig.changeset(%IdpConfig{}, attrs)
      refute changeset.valid?
      assert "missing required fields" <> _ = errors_on(changeset).config |> hd()
    end
  end
end

# test/secure_sharing/accounts/credential_test.exs
defmodule SecureSharing.Accounts.CredentialTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts.Credential

  describe "webauthn_changeset/2" do
    test "valid with required fields" do
      user = insert(:user)
      attrs = %{
        user_id: user.id,
        credential_id: :crypto.strong_rand_bytes(32),
        public_key: :crypto.strong_rand_bytes(64),
        device_name: "MacBook Pro"
      }

      changeset = Credential.webauthn_changeset(%Credential{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :type) == :webauthn
    end

    test "credential_id must be unique" do
      cred = insert(:credential, type: :webauthn)

      {:error, changeset} =
        %Credential{}
        |> Credential.webauthn_changeset(%{
          user_id: cred.user_id,
          credential_id: cred.credential_id,
          public_key: :crypto.strong_rand_bytes(64)
        })
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).credential_id
    end
  end

  describe "external_changeset/3" do
    test "valid OIDC credential" do
      user = insert(:user)
      attrs = %{user_id: user.id, external_id: "google-12345"}

      changeset = Credential.external_changeset(%Credential{}, attrs, :oidc)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :type) == :oidc
    end
  end
end
```

**Files to Create:**
```
mix.exs                              # Must include {:uuidv7, "~> 1.0"} dependency
config/
lib/secure_sharing/
  application.ex
  repo.ex
  schema.ex                        # Base schema using UUIDv7 type (from uuidv7 library)
  accounts/
    tenant.ex                      # Tenant schema (status, plan, billing fields)
    user.ex                        # User schema (role, vault fields)
    idp_config.ex                  # IdP configuration schema
    credential.ex                  # User credential schema
priv/repo/migrations/
  001_create_extensions.exs        # pgcrypto, pg_trgm
  002_create_enums.exs             # All enum types per 02-database-schema.md
  003_create_tenants.exs           # Tenants with status/plan
  004_create_users.exs             # Users with role/vault fields
  005_create_idp_configs.exs       # IdP configurations
  006_create_credentials.exs       # User credentials
  007_align_timestamps.exs         # created_at, TIMESTAMPTZ, triggers
test/
  support/
    data_case.ex
    factory.ex
  secure_sharing/
    accounts/
      tenant_test.exs
      user_test.exs
      idp_config_test.exs
      credential_test.exs
    schema_constraints_test.exs    # DB-level constraint tests
    migrations_test.exs            # Migration reversibility tests
```

---

### Phase 2: Crypto Core (Rust NIFs)

**Goals:**
- Integrate Rust crypto library via NIFs
- Implement signature verification
- Implement key wrap/unwrap operations
- Create Elixir wrapper with clean API

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Rust NIF package | Rustler-based crypto | NIFs load without error |
| ML-DSA verify | Signature verification | Test vectors pass |
| KAZ-SIGN verify | Signature verification | Test vectors pass |
| AES-256-GCM | Encrypt/decrypt | Round-trip tests pass |
| Key wrap | AES-KWP operations | Wrap/unwrap round-trip |
| Elixir API | High-level crypto module | Clean interface documented |

**Technical Features:**
- Rustler for NIF compilation
- Dirty schedulers for CPU-intensive operations
- Binary handling between Elixir/Rust
- Error handling with tagged tuples

**TDD Approach:**

```elixir
# test/secure_sharing/crypto_test.exs
defmodule SecureSharing.CryptoTest do
  use ExUnit.Case, async: true

  alias SecureSharing.Crypto

  # Test vectors from docs/crypto/07-test-vectors.md
  @ml_dsa_test_vector %{
    public_key: Base.decode64!("..."),
    message: "test message",
    signature: Base.decode64!("...")
  }

  describe "verify_signature/3" do
    test "verifies valid ML-DSA signature" do
      assert {:ok, true} = Crypto.verify_signature(
        :ml_dsa,
        @ml_dsa_test_vector.public_key,
        @ml_dsa_test_vector.message,
        @ml_dsa_test_vector.signature
      )
    end

    test "rejects tampered message" do
      assert {:ok, false} = Crypto.verify_signature(
        :ml_dsa,
        @ml_dsa_test_vector.public_key,
        "wrong message",
        @ml_dsa_test_vector.signature
      )
    end

    test "returns error for malformed signature" do
      assert {:error, :invalid_signature_format} = Crypto.verify_signature(
        :ml_dsa,
        @ml_dsa_test_vector.public_key,
        "message",
        <<0, 1, 2>>  # Too short
      )
    end
  end

  # AES-GCM API returns combined ciphertext || tag (16-byte tag appended)
  # This matches Erlang :crypto convention and simplifies the API.
  # For chunk storage per 03-encryption-protocol.md, format is: nonce || ciphertext || tag
  #
  # Function signatures:
  #   aes_gcm_encrypt(key, nonce, plaintext, aad) -> {:ok, ciphertext_with_tag}
  #   aes_gcm_decrypt(key, nonce, ciphertext_with_tag, aad) -> {:ok, plaintext}

  describe "aes_gcm_encrypt/4" do
    test "returns ciphertext with 16-byte tag appended" do
      key = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)
      plaintext = "secret data"
      aad = "additional data"

      {:ok, ciphertext_with_tag} = Crypto.aes_gcm_encrypt(key, nonce, plaintext, aad)

      # Output is ciphertext || tag (tag is always 16 bytes)
      assert byte_size(ciphertext_with_tag) == byte_size(plaintext) + 16
    end
  end

  describe "aes_gcm_decrypt/4" do
    test "decrypts valid ciphertext_with_tag" do
      key = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)
      plaintext = "secret data"
      aad = "additional data"

      {:ok, ciphertext_with_tag} = Crypto.aes_gcm_encrypt(key, nonce, plaintext, aad)
      assert {:ok, ^plaintext} = Crypto.aes_gcm_decrypt(key, nonce, ciphertext_with_tag, aad)
    end

    test "fails with wrong key" do
      key = :crypto.strong_rand_bytes(32)
      wrong_key = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)

      {:ok, ciphertext_with_tag} = Crypto.aes_gcm_encrypt(key, nonce, "data", "")
      assert {:error, :decryption_failed} = Crypto.aes_gcm_decrypt(wrong_key, nonce, ciphertext_with_tag, "")
    end

    test "fails with tampered ciphertext" do
      key = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)

      {:ok, ciphertext_with_tag} = Crypto.aes_gcm_encrypt(key, nonce, "data", "")
      <<first_byte, rest::binary>> = ciphertext_with_tag
      tampered = <<first_byte ^^^ 0xFF, rest::binary>>

      assert {:error, :decryption_failed} = Crypto.aes_gcm_decrypt(key, nonce, tampered, "")
    end
  end
end
```

**Files to Create:**
```
# Rust NIF code (standard Rustler location at project root)
native/secure_sharing_crypto/
  Cargo.toml
  src/
    lib.rs              # Rustler NIF entry point
    ml_dsa.rs           # ML-DSA-65 signatures
    kaz_sign.rs         # KAZ-SIGN hybrid signatures
    aes_gcm.rs          # AES-256-GCM encryption
    key_wrap.rs         # AES-256-KWP key wrapping

# Elixir NIF wrapper and crypto API
lib/secure_sharing/crypto.ex           # Public API (facade)
lib/secure_sharing/crypto/
  native.ex           # NIF bindings (Rustler module)
  signature.ex        # High-level signature operations
  symmetric.ex        # AES-GCM and key wrapping operations

test/secure_sharing/crypto_test.exs
test/secure_sharing/crypto/signature_test.exs
```

> **Note:** This is NOT an umbrella app. Rust NIFs go in `native/` at the project
> root (standard Rustler convention), not in a nested Mix project under `lib/`.

---

### Phase 3: Authentication & Identity (MVP: Email/Password)

**Goals:**
- Implement email/password authentication using `mix phx.gen.auth`
- Derive Master Key from password (Argon2id → HKDF)
- Create session management with JWT
- Build authentication plugs
- Prepare behaviour abstraction for future providers

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| User registration | Email/password signup | User created with encrypted keys |
| User login | Email/password auth | Session created, MK derivable |
| Password → MK derivation | Argon2id + HKDF | Keys correctly derived client-side |
| Session tokens | JWT issuance | Tokens validate correctly |
| Auth plugs | Request authentication | Protected routes require auth |
| Key bundle storage | Encrypted keys in DB | Keys stored/retrieved correctly |
| Provider behaviour | Interface for future IdPs | Abstraction ready for Passkeys/OIDC |

**Technical Features:**
- Phoenix `mix phx.gen.auth` as foundation
- Argon2id for password hashing (auth) AND key derivation (separate salt)
- HKDF for deriving MK encryption key from password
- JWT with short expiry + refresh tokens
- Behaviour-based provider abstraction (for future expansion)

**Key Derivation Flow (Client-Side):**
```
Password
    │
    ├──▶ Argon2id(password, auth_salt) ──▶ password_hash (sent to server for auth)
    │
    └──▶ Argon2id(password, key_salt) ──▶ HKDF("master-key") ──▶ MK encryption key
                                                                      │
                                                    Decrypt encrypted_master_key blob
                                                                      │
                                                                      ▼
                                                                Master Key (MK)
```

**TDD Approach:**

```elixir
# test/secure_sharing/accounts_test.exs
defmodule SecureSharing.AccountsTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts

  describe "register_user/1" do
    test "creates user with valid attributes" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        email: "user@example.com",
        password: "secure_password_123",
        public_keys: %{
          ml_kem: Base.encode64(<<1, 2, 3>>),
          ml_dsa: Base.encode64(<<4, 5, 6>>)
        },
        encrypted_private_keys: Base.encode64(<<7, 8, 9>>),
        encrypted_master_key: Base.encode64(<<10, 11, 12>>),
        key_derivation_salt: Base.encode64(:crypto.strong_rand_bytes(32))
      }

      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == "user@example.com"
      assert user.encrypted_master_key != nil
      assert user.key_derivation_salt != nil
      # Password hash stored, not plaintext
      refute user.password
      assert Argon2.verify_pass("secure_password_123", user.hashed_password)
    end

    test "fails with weak password" do
      attrs = %{email: "user@example.com", password: "short"}

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "fails with duplicate email in same tenant" do
      user = insert(:user)

      attrs = %{
        tenant_id: user.tenant_id,
        email: user.email,
        password: "secure_password_123"
      }

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "authenticate_user/2" do
    setup do
      user = insert(:user, password: "correct_password")
      {:ok, user: user}
    end

    test "returns user with correct password", %{user: user} do
      assert {:ok, authenticated_user} = Accounts.authenticate_user(
        user.email,
        "correct_password"
      )
      assert authenticated_user.id == user.id
    end

    test "returns error with wrong password", %{user: user} do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(
        user.email,
        "wrong_password"
      )
    end

    test "returns error for non-existent user" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(
        "nonexistent@example.com",
        "any_password"
      )
    end
  end

  describe "get_key_bundle/1" do
    test "returns user's encrypted key bundle" do
      user = insert(:user)

      assert {:ok, bundle} = Accounts.get_key_bundle(user)
      assert bundle.encrypted_master_key == user.encrypted_master_key
      assert bundle.encrypted_private_keys == user.encrypted_private_keys
      assert bundle.key_derivation_salt == user.key_derivation_salt
      assert bundle.public_keys == user.public_keys
    end
  end
end

# test/secure_sharing_web/controllers/auth_controller_test.exs
defmodule SecureSharingWeb.AuthControllerTest do
  use SecureSharingWeb.ConnCase, async: true

  describe "POST /api/v1/auth/register" do
    test "creates user and returns key bundle info", %{conn: conn} do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        email: "newuser@example.com",
        password: "secure_password_123",
        public_keys: %{ml_kem: "base64...", ml_dsa: "base64..."},
        encrypted_private_keys: "base64...",
        encrypted_master_key: "base64...",
        key_derivation_salt: "base64..."
      }

      conn = post(conn, ~p"/api/v1/auth/register", user: attrs)

      assert %{
        "user" => %{"id" => _, "email" => "newuser@example.com"},
        "token" => token
      } = json_response(conn, 201)

      assert is_binary(token)
    end
  end

  describe "POST /api/v1/auth/login" do
    setup do
      user = insert(:user, password: "test_password_123")
      {:ok, user: user}
    end

    test "returns token and key bundle on success", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/v1/auth/login", %{
        email: user.email,
        password: "test_password_123"
      })

      assert %{
        "token" => token,
        "key_bundle" => %{
          "encrypted_master_key" => _,
          "key_derivation_salt" => _,
          "encrypted_private_keys" => _,
          "public_keys" => _
        }
      } = json_response(conn, 200)

      assert is_binary(token)
    end

    test "returns error with invalid credentials", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/v1/auth/login", %{
        email: user.email,
        password: "wrong_password"
      })

      assert json_response(conn, 401)["error"] == "invalid_credentials"
    end
  end
end
```

**Files to Create:**
```
lib/secure_sharing/accounts/
  accounts.ex                    # Public API (extends phx.gen.auth)
  user.ex                        # User schema with key fields
  user_token.ex                  # Session tokens

lib/secure_sharing/identity/
  identity.ex                    # Provider abstraction
  session.ex                     # Session management
  providers/
    provider.ex                  # Behaviour (for future expansion)
    password.ex                  # Password provider (MVP)
    # Future: webauthn.ex, oidc.ex

lib/secure_sharing_web/plugs/
  authenticate.ex                # JWT verification
  require_auth.ex                # Require authenticated user
  tenant_context.ex              # Set tenant from user

lib/secure_sharing_web/controllers/
  auth_controller.ex             # Register, login, logout
  auth_json.ex                   # JSON views

priv/repo/migrations/
  003_add_key_fields_to_users.exs  # Add crypto key columns

test/secure_sharing/accounts_test.exs
test/secure_sharing_web/controllers/auth_controller_test.exs
```

---

### Phase 4: Storage Context (Files & Folders)

**Goals:**
- Implement file metadata storage
- Implement folder hierarchy
- Integrate S3 blob storage
- Build upload/download endpoints

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| File schema | File metadata storage | CRUD operations work |
| Folder schema | Hierarchical folders | Parent-child queries work |
| Blob store | S3 upload/download | Files persist to S3 |
| Upload endpoint | Chunked uploads | Large files upload successfully |
| Download endpoint | Streaming downloads | Files stream without memory issues |
| Signature verification | Verify on access | Invalid signatures rejected |

**Technical Features:**
- Ecto `belongs_to` for folder hierarchy
- `ExAws.S3` for object storage
- Streaming uploads with `Plug.Conn.read_body/2`
- Presigned URLs for direct client access

**TDD Approach:**

```elixir
# test/secure_sharing/storage_test.exs
defmodule SecureSharing.StorageTest do
  use SecureSharing.DataCase, async: true
  import Mox

  alias SecureSharing.Storage

  setup :verify_on_exit!

  describe "create_folder/2" do
    test "creates root folder for user" do
      user = insert(:user)

      assert {:ok, folder} = Storage.create_folder(user, %{
        encrypted_metadata: <<1, 2, 3>>,
        metadata_nonce: <<4, 5, 6>>,
        wrapped_kek: <<7, 8, 9>>,
        owner_key_access: %{
          wrapped_kek: <<>>,
          kem_ciphertexts: []
        },
        signature: %{ml_dsa: <<>>, kaz_sign: <<>>}
      })

      assert folder.owner_id == user.id
      assert folder.parent_id == nil
    end

    test "creates child folder" do
      user = insert(:user)
      parent = insert(:folder, owner: user)

      assert {:ok, child} = Storage.create_folder(user, %{
        parent_id: parent.id,
        encrypted_metadata: <<>>,
        # ... other fields
      })

      assert child.parent_id == parent.id
    end
  end

  describe "get_file/2 with signature verification" do
    test "returns file when signature is valid" do
      file = insert(:file)

      # Mock signature verification
      expect(SecureSharing.Crypto.Mock, :verify_combined_signature, fn _, _, _ ->
        {:ok, true}
      end)

      assert {:ok, returned_file} = Storage.get_file(file.owner, file.id)
      assert returned_file.id == file.id
    end

    test "returns error when signature is invalid" do
      file = insert(:file)

      expect(SecureSharing.Crypto.Mock, :verify_combined_signature, fn _, _, _ ->
        {:ok, false}
      end)

      assert {:error, :signature_invalid} = Storage.get_file(file.owner, file.id)
    end
  end

  describe "upload_blob/3" do
    test "uploads file to S3" do
      file = insert(:file)
      blob = :crypto.strong_rand_bytes(1024)

      expect(SecureSharing.Storage.BlobStoreMock, :put, fn _key, _blob, _opts ->
        {:ok, %{}}
      end)

      assert :ok = Storage.upload_blob(file, blob, content_type: "application/octet-stream")
    end
  end
end

# test/secure_sharing_web/controllers/file_controller_test.exs
defmodule SecureSharingWeb.FileControllerTest do
  use SecureSharingWeb.ConnCase, async: true

  describe "POST /api/v1/files" do
    setup [:authenticate_user]

    test "creates file metadata", %{conn: conn, user: user} do
      folder = insert(:folder, owner: user)

      attrs = %{
        folder_id: folder.id,
        encrypted_metadata: Base.encode64(<<1, 2, 3>>),
        metadata_nonce: Base.encode64(<<4, 5, 6>>),
        wrapped_dek: Base.encode64(<<7, 8, 9>>),
        blob_size: 1024,
        blob_hash: "abc123",
        signature: %{ml_dsa: "...", kaz_sign: "..."}
      }

      conn = post(conn, ~p"/api/v1/files", file: attrs)

      assert %{"id" => id} = json_response(conn, 201)["data"]
      assert Storage.get_file!(id)
    end
  end

  describe "GET /api/v1/files/:id/blob" do
    test "streams file content", %{conn: conn, user: user} do
      file = insert(:file, owner: user)
      blob = :crypto.strong_rand_bytes(10_000)

      expect(SecureSharing.Storage.BlobStoreMock, :get_stream, fn _key ->
        {:ok, [blob]}
      end)

      conn = get(conn, ~p"/api/v1/files/#{file.id}/blob")

      assert response(conn, 200) == blob
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end
  end
end
```

**Files to Create:**
```
lib/secure_sharing/storage/
  storage.ex                     # Public API
  file.ex                        # File schema
  folder.ex                      # Folder schema
  blob_store.ex                  # Behaviour
  blob_stores/
    s3.ex                        # S3 implementation
    local.ex                     # Local filesystem (dev)
  upload_coordinator.ex          # GenServer for chunked uploads

lib/secure_sharing_web/controllers/
  file_controller.ex
  folder_controller.ex

priv/repo/migrations/
  004_create_folders.exs
  005_create_files.exs

test/secure_sharing/storage_test.exs
test/secure_sharing/storage/folder_test.exs
test/secure_sharing_web/controllers/file_controller_test.exs
```

---

### Phase 5: Sharing Context

**Goals:**
- Implement share grants (user-to-user)
- Implement share links (anonymous)
- Build share management endpoints
- Implement signature verification for shares

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Share grant schema | User-to-user shares | Grants store correctly |
| Share link schema | Anonymous links | Links generate/resolve |
| Grant verification | Signature check | Invalid grants rejected |
| Permission checks | Access control | Permissions enforced |
| Share API | CRUD endpoints | All operations work |
| Notification | Share notifications | Recipients notified |

**Technical Features:**
- Combined signature verification (ML-DSA + KAZ-SIGN)
- Token generation for share links
- Permission inheritance for folders
- PubSub for notifications

**TDD Approach:**

```elixir
# test/secure_sharing/sharing_test.exs
defmodule SecureSharing.SharingTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Sharing

  describe "create_share_grant/3" do
    setup do
      owner = insert(:user)
      recipient = insert(:user, tenant: owner.tenant)
      file = insert(:file, owner: owner)
      {:ok, owner: owner, recipient: recipient, file: file}
    end

    test "creates share with valid signature", ctx do
      attrs = %{
        resource_type: :file,
        resource_id: ctx.file.id,
        grantee_id: ctx.recipient.id,
        wrapped_key: <<1, 2, 3>>,
        kem_ciphertexts: [%{algorithm: "ML-KEM-768", ciphertext: <<>>}],
        permission: :read,
        signature: %{ml_dsa: <<>>, kaz_sign: <<>>}
      }

      # Mock signature verification
      expect_signature_valid()

      assert {:ok, grant} = Sharing.create_share_grant(ctx.owner, ctx.file, attrs)
      assert grant.grantor_id == ctx.owner.id
      assert grant.grantee_id == ctx.recipient.id
    end

    test "rejects share with invalid signature", ctx do
      expect_signature_invalid()

      assert {:error, :signature_invalid} = Sharing.create_share_grant(
        ctx.owner,
        ctx.file,
        %{signature: %{ml_dsa: <<>>, kaz_sign: <<>>}}
      )
    end

    test "owner cannot share without admin permission", ctx do
      file = insert(:file)  # Different owner

      assert {:error, :permission_denied} = Sharing.create_share_grant(
        ctx.owner,
        file,
        %{}
      )
    end
  end

  describe "get_file_via_share/2" do
    test "returns file when share is valid" do
      grant = insert(:share_grant, resource_type: :file)

      expect_signature_valid()  # Share grant signature
      expect_signature_valid()  # File signature

      assert {:ok, file, share_info} = Sharing.get_file_via_share(
        grant.grantee,
        grant.id
      )

      assert file.id == grant.resource_id
      assert share_info.permission == grant.permission
    end

    test "returns error for expired share" do
      grant = insert(:share_grant, expiry: DateTime.add(DateTime.utc_now(), -1, :day))

      assert {:error, :share_expired} = Sharing.get_file_via_share(
        grant.grantee,
        grant.id
      )
    end
  end

  describe "create_share_link/2" do
    test "creates link with password protection" do
      file = insert(:file)

      assert {:ok, link} = Sharing.create_share_link(file.owner, file, %{
        password_protected: true,
        password_hash: Argon2.hash_pwd_salt("secret"),
        max_downloads: 5,
        signature: %{}
      })

      assert link.password_protected == true
      assert String.length(link.token) == 32
    end
  end
end
```

**Files to Create:**
```
lib/secure_sharing/sharing/
  sharing.ex                     # Public API
  share_grant.ex                 # Grant schema
  share_link.ex                  # Link schema
  permission.ex                  # Permission logic

lib/secure_sharing_web/controllers/
  share_controller.ex            # Share endpoints
  share_link_controller.ex       # Link endpoints

priv/repo/migrations/
  006_create_share_grants.exs
  007_create_share_links.exs

test/secure_sharing/sharing_test.exs
test/secure_sharing_web/controllers/share_controller_test.exs
```

---

### Phase 6: Recovery System

**Goals:**
- Implement Shamir share storage
- Build recovery request flow
- Implement trustee approval
- Handle share reconstruction

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Recovery share schema | Trustee shares storage | Shares store correctly |
| Recovery request | Request initiation | Requests create/track |
| Trustee approval | Approval workflow | Approvals record correctly |
| Threshold check | k-of-n validation | Reconstruction triggers at threshold |
| Notification | Trustee notifications | Trustees notified of requests |
| Expiry handling | Auto-expire requests | Stale requests cleaned up |

**Technical Features:**
- Encrypted share storage
- Oban jobs for notifications
- State machine for request lifecycle
- Threshold tracking

**TDD Approach:**

```elixir
# test/secure_sharing/recovery_test.exs
defmodule SecureSharing.RecoveryTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Recovery

  describe "initiate_recovery/2" do
    setup do
      user = insert(:user, recovery_setup_complete: true)
      trustees = insert_list(5, :recovery_share, user: user)
      {:ok, user: user, trustees: trustees}
    end

    test "creates recovery request", %{user: user} do
      assert {:ok, request} = Recovery.initiate_recovery(user, %{
        reason: :device_lost,
        new_public_keys: %{ml_kem: "...", ml_dsa: "..."}
      })

      assert request.status == :pending
      assert request.user_id == user.id
    end

    test "fails if recovery not set up" do
      user = insert(:user, recovery_setup_complete: false)

      assert {:error, :recovery_not_setup} = Recovery.initiate_recovery(user, %{})
    end
  end

  describe "approve_recovery/3" do
    setup do
      request = insert(:recovery_request, status: :pending)
      trustee = insert(:recovery_share, user: request.user)
      {:ok, request: request, trustee: trustee}
    end

    test "records approval with re-encrypted share", %{request: request, trustee: trustee} do
      assert {:ok, approval} = Recovery.approve_recovery(
        trustee.trustee_user,
        request.id,
        %{
          re_encrypted_share: <<1, 2, 3>>,
          kem_ciphertext: <<4, 5, 6>>,
          signature: %{}
        }
      )

      assert approval.recovery_request_id == request.id
    end

    test "completes recovery when threshold reached", %{request: request} do
      # Create k-1 approvals
      insert_list(2, :recovery_approval, recovery_request: request)

      # This should be the kth approval (threshold = 3)
      trustee = insert(:recovery_share, user: request.user)

      assert {:ok, _approval, :completed} = Recovery.approve_recovery(
        trustee.trustee_user,
        request.id,
        %{re_encrypted_share: <<>>, kem_ciphertext: <<>>, signature: %{}}
      )

      # Request should be marked complete
      updated = Repo.get!(Recovery.Request, request.id)
      assert updated.status == :completed
    end
  end
end
```

**Files to Create:**
```
lib/secure_sharing/recovery/
  recovery.ex                    # Public API
  recovery_share.ex              # Shamir share schema
  recovery_request.ex            # Request schema
  recovery_approval.ex           # Approval schema
  coordinator.ex                 # Reconstruction logic

lib/secure_sharing/workers/
  recovery_notification_worker.ex
  recovery_expiry_worker.ex

lib/secure_sharing_web/controllers/
  recovery_controller.ex

priv/repo/migrations/
  008_create_recovery_shares.exs
  009_create_recovery_requests.exs
  010_create_recovery_approvals.exs

test/secure_sharing/recovery_test.exs
```

---

### Phase 7: Real-Time Features (Channels)

**Goals:**
- Implement folder presence
- Build live notifications
- Add upload progress broadcasting

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| User socket | Authenticated WebSocket | Connections authenticate |
| Folder channel | Real-time folder updates | File changes broadcast |
| Presence | "Who's viewing" | Presence tracks correctly |
| Notifications | Share/recovery alerts | Users receive notifications |

**Technical Features:**
- Phoenix Channels
- Phoenix Presence
- PubSub integration

**TDD Approach:**

```elixir
# test/secure_sharing_web/channels/folder_channel_test.exs
defmodule SecureSharingWeb.FolderChannelTest do
  use SecureSharingWeb.ChannelCase

  alias SecureSharingWeb.FolderChannel

  setup do
    user = insert(:user)
    folder = insert(:folder, owner: user)
    {:ok, _, socket} = socket(SecureSharingWeb.UserSocket, "user:#{user.id}", %{user: user})
      |> subscribe_and_join(FolderChannel, "folder:#{folder.id}")

    {:ok, socket: socket, user: user, folder: folder}
  end

  test "broadcasts file_added when file created", %{socket: socket, folder: folder} do
    file = insert(:file, folder: folder)

    SecureSharingWeb.Endpoint.broadcast(
      "folder:#{folder.id}",
      "file_added",
      %{id: file.id, name: "encrypted..."}
    )

    assert_push "file_added", %{id: _}
  end

  test "tracks presence when user joins", %{socket: socket, user: user, folder: folder} do
    presence = SecureSharingWeb.Presence.list("folder:#{folder.id}")
    assert Map.has_key?(presence, "#{user.id}")
  end
end
```

**Files to Create:**
```
lib/secure_sharing_web/channels/
  user_socket.ex
  folder_channel.ex
  notification_channel.ex
  presence.ex

test/secure_sharing_web/channels/
  folder_channel_test.exs
  notification_channel_test.exs
```

---

### Phase 8: Admin Portal (LiveView)

**Goals:**
- Build tenant management UI
- Build user management UI
- Create system dashboard
- Implement audit log viewer

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Dashboard | System overview | Stats display correctly |
| Tenant management | CRUD tenants | All operations work |
| User management | View/suspend users | Admin actions work |
| Audit log | Event viewer | Logs filter/paginate |

**Technical Features:**
- Phoenix LiveView
- LiveView Components
- Real-time updates via PubSub

**TDD Approach:**

```elixir
# test/secure_sharing_web/live/admin/dashboard_live_test.exs
defmodule SecureSharingWeb.Admin.DashboardLiveTest do
  use SecureSharingWeb.ConnCase
  import Phoenix.LiveViewTest

  setup [:authenticate_admin]

  test "displays system stats", %{conn: conn} do
    insert_list(5, :tenant)
    insert_list(10, :user)

    {:ok, view, html} = live(conn, ~p"/admin")

    assert html =~ "5 Tenants"
    assert html =~ "10 Users"
  end

  test "updates in real-time when tenant created", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin")

    # Simulate tenant creation
    {:ok, tenant} = Accounts.create_tenant(%{name: "New Tenant", slug: "new"})

    # Should update via PubSub
    assert render(view) =~ "New Tenant"
  end
end
```

**Files to Create:**
```
lib/secure_sharing_web/live/
  admin/
    dashboard_live.ex
    dashboard_live.html.heex
    tenant_live/
      index.ex
      show.ex
      form_component.ex
    user_live/
      index.ex
      show.ex
    audit_live/
      index.ex
  components/
    admin_components.ex

test/secure_sharing_web/live/admin/
  dashboard_live_test.exs
  tenant_live_test.exs
```

---

### Phase 9: Multi-Tenancy & Production Hardening

**Goals:**
- Implement tenant isolation
- Add rate limiting
- Configure production deployment
- Performance optimization

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| Tenant isolation | Query scoping | Cross-tenant access prevented |
| Rate limiting | Per-tenant limits | Limits enforced |
| Connection pooling | DB pool tuning | High concurrency stable |
| Caching | ETS/Redis caching | Response times improved |
| Clustering | Distributed Erlang | Multi-node works |
| Releases | Mix releases | Production deployable |

**Technical Features:**
- Ecto multi-tenancy via query prefixes or scoping
- Hammer for rate limiting
- Cachex or ETS for caching
- libcluster for clustering

**TDD Approach:**

```elixir
# test/secure_sharing/multi_tenancy_test.exs
defmodule SecureSharing.MultiTenancyTest do
  use SecureSharing.DataCase, async: true

  describe "tenant isolation" do
    test "user cannot access other tenant's files" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      user_a = insert(:user, tenant: tenant_a)
      user_b = insert(:user, tenant: tenant_b)
      file = insert(:file, owner: user_a)

      assert {:error, :not_found} = Storage.get_file(user_b, file.id)
    end

    test "queries are scoped to tenant" do
      tenant = insert(:tenant)
      other_tenant = insert(:tenant)

      insert_list(5, :file, tenant: tenant)
      insert_list(3, :file, tenant: other_tenant)

      files = Storage.list_files(tenant)
      assert length(files) == 5
    end
  end
end

# test/secure_sharing/rate_limit_test.exs
defmodule SecureSharing.RateLimitTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.RateLimiter

  test "allows requests under limit" do
    user = insert(:user)

    for _ <- 1..100 do
      assert :ok = RateLimiter.check(user, :api_request)
    end
  end

  test "blocks requests over limit" do
    user = insert(:user)

    # Exhaust limit
    for _ <- 1..1000, do: RateLimiter.check(user, :api_request)

    assert {:error, :rate_limited, retry_after} = RateLimiter.check(user, :api_request)
    assert is_integer(retry_after)
  end
end
```

**Files to Create:**
```
lib/secure_sharing/
  rate_limiter.ex
  cache.ex

lib/secure_sharing_web/plugs/
  rate_limit.ex

config/runtime.exs                # Production config
rel/
  env.sh.eex

test/secure_sharing/multi_tenancy_test.exs
test/secure_sharing/rate_limit_test.exs
```

---

### Phase 10: Integration Testing & Documentation

**Goals:**
- Complete end-to-end tests
- API documentation
- Deployment guides
- Performance benchmarks

**Deliverables:**

| Deliverable | Description | Acceptance Criteria |
|-------------|-------------|---------------------|
| E2E tests | Full flow tests | All flows pass |
| API docs | OpenAPI spec | Spec validates |
| Deployment guide | Production setup | Reproducible deploy |
| Benchmarks | Performance tests | Baseline established |

**Files to Create:**
```
test/integration/
  full_upload_flow_test.exs
  full_share_flow_test.exs
  full_recovery_flow_test.exs

docs/
  deployment/
    01-production-setup.md
    02-clustering.md
    03-monitoring.md
  api/
    openapi.yaml
```

---

## 7. Elixir/OTP Best Practices Summary

### Do's

| Practice | Reason |
|----------|--------|
| Use Contexts for domain boundaries | Clear APIs, testable |
| Use Behaviours for abstractions | Mockable, swappable |
| Use Supervision trees | Fault isolation |
| Use pattern matching extensively | Readable, explicit |
| Use `with` for sequential operations | Clean error handling |
| Write tests first (TDD) | Confidence, design feedback |
| Use Mox for mocking | Behaviour-based, explicit |
| Keep processes short-lived | Avoid memory leaks |
| Use ETS for hot data | Low-latency reads |
| Use Oban for background jobs | Reliable, persistent |

### Don'ts

| Anti-Pattern | Why to Avoid |
|--------------|--------------|
| Cross-context internal calls | Breaks encapsulation |
| Long-running GenServer calls | Blocks callers |
| Mutable state outside processes | Race conditions |
| Catch-all error handling | Hides bugs |
| Premature optimization | Waste of time |
| Skipping tests | Technical debt |
| Using global state | Hard to test/reason about |
| Ignoring OTP principles | Missing BEAM benefits |

---

## 8. Milestone Summary

| Phase | Key Outcome | Test Coverage Target |
|-------|-------------|---------------------|
| 1 | Running Phoenix app with schemas | 100% schema tests |
| 2 | Working crypto NIFs | 100% + property tests |
| 3 | User authentication working | 100% auth flows |
| 4 | File upload/download working | 100% storage ops |
| 5 | Sharing between users working | 100% share logic |
| 6 | Recovery flow complete | 100% recovery paths |
| 7 | Real-time updates working | 100% channel tests |
| 8 | Admin portal functional | 90% LiveView tests |
| 9 | Production-ready | Performance benchmarks |
| 10 | Fully documented | E2E coverage |

---

## 9. Dependencies (mix.exs)

```elixir
defp deps do
  [
    # Phoenix
    {:phoenix, "~> 1.7.0"},
    {:phoenix_ecto, "~> 4.4"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_live_dashboard, "~> 0.8"},

    # Database
    {:ecto_sql, "~> 3.11"},
    {:postgrex, "~> 0.17"},
    {:uuidv7, "~> 1.0"},         # UUIDv7 Ecto type for time-ordered primary keys

    # Auth (MVP: Email/Password)
    {:bcrypt_elixir, "~> 3.0"},  # Password hashing (phx.gen.auth default)
    {:argon2_elixir, "~> 4.0"},  # Key derivation (separate from auth hash)
    {:joken, "~> 2.6"},          # JWT tokens

    # Auth (Future: Passkeys, OIDC)
    # {:wax_, "~> 0.6"},         # WebAuthn (add when implementing Passkeys)
    # {:assent, "~> 0.2"},       # OIDC (add when implementing SSO)

    # Crypto
    {:rustler, "~> 0.30"},       # Rust NIFs

    # Background Jobs
    {:oban, "~> 2.17"},

    # HTTP Client
    {:req, "~> 0.4"},

    # AWS/S3
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},

    # Rate Limiting
    {:hammer, "~> 6.1"},

    # Clustering
    {:libcluster, "~> 3.3"},

    # Telemetry
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},

    # Dev/Test
    {:phoenix_live_reload, "~> 1.4", only: :dev},
    {:mox, "~> 1.1", only: :test},
    {:ex_machina, "~> 2.7", only: :test},
    {:stream_data, "~> 0.6", only: :test},
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

---

## 10. Getting Started

```bash
# Create project
mix phx.new secure_sharing --database postgres --no-html --no-assets

# Add dependencies to mix.exs, then:
mix deps.get

# Create database
mix ecto.create

# Run tests (TDD - write tests first!)
mix test

# Start server
mix phx.server
```

**Development Workflow:**

1. Write failing test
2. Run `mix test` - confirm failure
3. Implement minimal code
4. Run `mix test` - confirm pass
5. Refactor if needed
6. Run `mix credo` - check style
7. Run `mix dialyzer` - check types
8. Commit

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.0.0 | 2026-01 | Initial development plan |
