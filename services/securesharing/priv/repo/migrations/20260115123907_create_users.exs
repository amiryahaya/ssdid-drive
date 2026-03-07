defmodule SecureSharing.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      # UUIDv7 primary key
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Tenant relationship
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false

      # Basic info
      add :email, :string, null: false
      add :status, :user_status, null: false, default: "active"

      # Authentication (MVP: password-based)
      add :hashed_password, :string

      # Zero-knowledge key storage
      # Public keys - visible to server, used for key encapsulation
      add :public_keys, :map, null: false, default: %{}
      # Encrypted private keys - encrypted by Master Key, opaque to server
      add :encrypted_private_keys, :binary
      # Master Key encrypted by password-derived key
      add :encrypted_master_key, :binary
      # Salt for password-based key derivation (separate from auth hash)
      add :key_derivation_salt, :binary

      # Recovery
      add :recovery_setup_complete, :boolean, default: false

      # Confirmed email
      add :confirmed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:tenant_id, :email])
    create index(:users, [:tenant_id])
    create index(:users, [:status])

    # User tokens for session management
    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
