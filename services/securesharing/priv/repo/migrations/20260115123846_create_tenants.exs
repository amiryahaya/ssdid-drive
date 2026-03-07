defmodule SecureSharing.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      # UUIDv7 primary key - time-ordered for better index performance
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      add :name, :string, null: false
      add :slug, :string, null: false

      # Limits
      # 10 GB default
      add :storage_quota_bytes, :bigint, default: 10_737_418_240
      add :max_users, :integer, default: 100

      # Settings
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])
  end
end
