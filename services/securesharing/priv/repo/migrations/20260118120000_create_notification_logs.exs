defmodule SecureSharing.Repo.Migrations.CreateNotificationLogs do
  use Ecto.Migration

  def change do
    create table(:notification_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text, null: false
      add :notification_type, :string, null: false
      add :recipient_count, :integer, default: 0
      add :recipient_ids, {:array, :binary_id}, default: []
      add :data, :map, default: %{}
      add :status, :string, default: "pending"
      add :error_message, :text
      add :onesignal_id, :string
      add :sent_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_logs, [:sent_by_id])
    create index(:notification_logs, [:notification_type])
    create index(:notification_logs, [:status])
    create index(:notification_logs, [:inserted_at])
  end
end
