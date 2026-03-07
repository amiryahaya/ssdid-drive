defmodule SecureSharing.Repo.Migrations.CreateDeviceEnrollments do
  @moduledoc """
  Create device_enrollments table for user-device bindings.

  Each enrollment represents a user's cryptographic binding to a device.
  The device_public_key is used to verify request signatures from that device.
  """
  use Ecto.Migration

  def up do
    # Create enums for enrollment-related types
    execute """
    DO $$ BEGIN
      CREATE TYPE device_key_algorithm AS ENUM ('kaz_sign', 'ml_dsa');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """

    execute """
    DO $$ BEGIN
      CREATE TYPE enrollment_status AS ENUM ('active', 'revoked');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """

    create table(:device_enrollments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Relationships
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      # Cryptographic material
      add :device_public_key, :binary, null: false
      add :key_algorithm, :device_key_algorithm, null: false

      # Metadata
      add :device_name, :string, size: 128

      # Status
      add :status, :enrollment_status, null: false, default: "active"
      add :revoked_at, :utc_datetime_usec
      add :revoked_reason, :string, size: 256

      # Activity tracking
      add :enrolled_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
      add :last_used_at, :utc_datetime_usec

      # Timestamps (using created_at to match schema)
      add :created_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    # Unique constraint: one enrollment per user per device
    create unique_index(:device_enrollments, [:device_id, :user_id])

    # Indexes for common queries
    create index(:device_enrollments, [:device_id])
    create index(:device_enrollments, [:user_id])
    create index(:device_enrollments, [:tenant_id])
    create index(:device_enrollments, [:user_id, :status])
    create index(:device_enrollments, [:device_id, :status])
  end

  def down do
    drop table(:device_enrollments)

    execute "DROP TYPE IF EXISTS enrollment_status"
    execute "DROP TYPE IF EXISTS device_key_algorithm"
  end
end
