defmodule SecureSharing.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    # Invitation status enum
    execute(
      "CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked')",
      "DROP TYPE invitation_status"
    )

    # Invitation role enum (what role the invitee will have)
    execute(
      "CREATE TYPE invitation_role AS ENUM ('admin', 'manager', 'member')",
      "DROP TYPE invitation_role"
    )

    create table(:invitations, primary_key: false) do
      # UUIDv7 primary key
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Token for invitation link (stored as hash for security)
      add :token_hash, :string, null: false

      # Invitation details
      add :email, :string, null: false
      add :role, :invitation_role, null: false, default: "member"
      add :message, :text

      # Relationships
      add :tenant_id, references(:tenants, type: :uuid, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      # Status tracking
      add :status, :invitation_status, null: false, default: "pending"

      # Expiration
      add :expires_at, :utc_datetime_usec, null: false

      # Acceptance tracking
      add :accepted_at, :utc_datetime_usec
      add :accepted_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      # Additional metadata (pre-shared folders, etc.)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    # Unique index on token hash for lookups
    create unique_index(:invitations, [:token_hash])

    # Index for email lookup (find pending invitations for an email)
    create index(:invitations, [:email])

    # Index for tenant invitations
    create index(:invitations, [:tenant_id])

    # Index for inviter's sent invitations
    create index(:invitations, [:inviter_id])

    # Index for status filtering
    create index(:invitations, [:status])

    # Partial index for pending invitations by expiry (for cleanup job)
    create index(:invitations, [:expires_at],
             where: "status = 'pending'",
             name: :idx_invitations_pending_expires_at
           )

    # Composite index for finding existing pending invitation for email in tenant
    create unique_index(:invitations, [:tenant_id, :email],
             where: "status = 'pending'",
             name: :idx_invitations_pending_email_per_tenant
           )
  end
end
