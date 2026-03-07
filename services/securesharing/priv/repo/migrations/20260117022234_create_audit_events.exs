defmodule SecureSharing.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :ip_address, :string
      add :user_agent, :string
      add :metadata, :map, default: %{}
      add :status, :string, null: false, default: "success"
      add :error_message, :text

      timestamps(updated_at: false)
    end

    create index(:audit_events, [:tenant_id])
    create index(:audit_events, [:user_id])
    create index(:audit_events, [:action])
    create index(:audit_events, [:resource_type])
    create index(:audit_events, [:resource_type, :resource_id])
    create index(:audit_events, [:inserted_at])
    create index(:audit_events, [:tenant_id, :inserted_at])
    create index(:audit_events, [:tenant_id, :action])
    create index(:audit_events, [:tenant_id, :user_id, :inserted_at])
  end
end
