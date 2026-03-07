defmodule SecureSharing.Repo.Migrations.CreateUserNotifications do
  use Ecto.Migration

  def change do
    create table(:user_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :data, :map, default: %{}
      add :read_at, :utc_datetime_usec
      add :dismissed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_notifications, [:user_id])
    create index(:user_notifications, [:user_id, :read_at])
    create index(:user_notifications, [:user_id, :inserted_at])
    create index(:user_notifications, [:type])
  end
end
