defmodule SecureSharing.Repo.Migrations.CreateAccessRequests do
  use Ecto.Migration

  def change do
    create table(:access_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :share_grant_id, references(:share_grants, type: :binary_id, on_delete: :delete_all), null: false
      add :requester_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :requested_permission, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :reason, :text
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec

      timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
    end

    create index(:access_requests, [:share_grant_id])
    create index(:access_requests, [:requester_id])
    create index(:access_requests, [:tenant_id, :status])

    # Only one pending request per share grant
    create unique_index(:access_requests, [:share_grant_id],
      where: "status = 'pending'",
      name: :access_requests_one_pending_per_share
    )
  end
end
