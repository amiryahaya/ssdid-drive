defmodule SecureSharing.Repo.Migrations.CreateDevices do
  @moduledoc """
  Create devices table for device attestation and enrollment.

  Devices represent physical devices that users can enroll for secure access.
  Each device can have multiple user enrollments (for shared devices).
  """
  use Ecto.Migration

  def up do
    # Create enums for device-related types
    execute """
    DO $$ BEGIN
      CREATE TYPE device_platform AS ENUM ('android', 'ios', 'windows', 'macos', 'linux', 'other');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """

    execute """
    DO $$ BEGIN
      CREATE TYPE device_status AS ENUM ('active', 'suspended');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """

    execute """
    DO $$ BEGIN
      CREATE TYPE device_trust_level AS ENUM ('high', 'medium', 'low');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """

    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Device identification
      add :device_fingerprint, :string, null: false, size: 128

      # Platform info
      add :platform, :device_platform, null: false
      add :device_info, :map, null: false, default: %{}

      # Platform attestation (Phase 2)
      add :platform_attestation, :binary
      add :attestation_verified_at, :utc_datetime_usec

      # Status
      add :status, :device_status, null: false, default: "active"
      add :trust_level, :device_trust_level, null: false, default: "medium"

      # Timestamps (using created_at to match schema)
      add :created_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    # Indexes
    create index(:devices, [:device_fingerprint])
    create index(:devices, [:status])
    create index(:devices, [:platform])
  end

  def down do
    drop table(:devices)

    execute "DROP TYPE IF EXISTS device_trust_level"
    execute "DROP TYPE IF EXISTS device_status"
    execute "DROP TYPE IF EXISTS device_platform"
  end
end
