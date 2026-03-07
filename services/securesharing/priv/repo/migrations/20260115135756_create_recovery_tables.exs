defmodule SecureSharing.Repo.Migrations.CreateRecoveryTables do
  use Ecto.Migration

  def change do
    # =========================================================================
    # Recovery Configuration - per-user recovery settings
    # =========================================================================
    create table(:recovery_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Shamir parameters
      # k shares needed
      add :threshold, :integer, null: false, default: 3
      # n total shares
      add :total_shares, :integer, null: false, default: 5

      # Status
      add :setup_complete, :boolean, default: false, null: false
      add :last_verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:recovery_configs, [:user_id])

    # =========================================================================
    # Recovery Shares - Shamir shares distributed to trustees
    # =========================================================================
    create table(:recovery_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :config_id, references(:recovery_configs, type: :binary_id, on_delete: :delete_all),
        null: false

      # The user whose key this share helps recover
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # The trustee holding this share
      add :trustee_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Share index (1 to n) for Shamir reconstruction
      add :share_index, :integer, null: false

      # The encrypted share - encrypted with trustee's public key
      add :encrypted_share, :binary, null: false

      # KEM ciphertext for decrypting the share
      add :kem_ciphertext, :binary, null: false

      # Owner's signature over the share
      add :signature, :binary, null: false

      # Status
      add :accepted, :boolean, default: false, null: false
      add :accepted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Index for listing shares held by a trustee
    create index(:recovery_shares, [:trustee_id])

    # Index for listing shares for a user's recovery
    create index(:recovery_shares, [:owner_id])

    # Ensure unique share per trustee per owner
    create unique_index(:recovery_shares, [:owner_id, :trustee_id])

    # Ensure unique share index per config
    create unique_index(:recovery_shares, [:config_id, :share_index])

    # =========================================================================
    # Recovery Requests - requests from users who lost access
    # =========================================================================
    execute(
      "CREATE TYPE recovery_request_status AS ENUM ('pending', 'approved', 'rejected', 'completed', 'expired')",
      "DROP TYPE recovery_request_status"
    )

    create table(:recovery_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :config_id, references(:recovery_configs, type: :binary_id, on_delete: :delete_all),
        null: false

      # User requesting recovery
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # New public key the user generated for recovery
      add :new_public_key, :binary, null: false

      # Request details
      add :reason, :string
      add :status, :recovery_request_status, null: false, default: "pending"

      # Verification (optional - organization can require identity verification)
      add :verified_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :verified_at, :utc_datetime_usec

      # Expiry
      add :expires_at, :utc_datetime_usec, null: false

      # Completion
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:recovery_requests, [:user_id])
    create index(:recovery_requests, [:status])

    # =========================================================================
    # Recovery Approvals - trustees approving recovery requests
    # =========================================================================
    create table(:recovery_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :request_id, references(:recovery_requests, type: :binary_id, on_delete: :delete_all),
        null: false

      add :share_id, references(:recovery_shares, type: :binary_id, on_delete: :delete_all),
        null: false

      # Trustee approving
      add :trustee_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # The share re-encrypted for the user's new public key
      add :reencrypted_share, :binary, null: false

      # KEM ciphertext for the new key
      add :kem_ciphertext, :binary, null: false

      # Trustee's signature approving this recovery
      add :signature, :binary, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Index for listing approvals for a request
    create index(:recovery_approvals, [:request_id])

    # Ensure one approval per trustee per request
    create unique_index(:recovery_approvals, [:request_id, :trustee_id])
  end
end
