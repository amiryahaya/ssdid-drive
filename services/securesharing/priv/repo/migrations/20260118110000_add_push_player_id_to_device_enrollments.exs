defmodule SecureSharing.Repo.Migrations.AddPushPlayerIdToDeviceEnrollments do
  use Ecto.Migration

  def change do
    alter table(:device_enrollments) do
      # OneSignal player_id for push notifications
      # This is the unique identifier assigned by OneSignal to each device
      add :push_player_id, :string
    end

    # Index for looking up enrollments by player_id
    create index(:device_enrollments, [:push_player_id])
  end
end
