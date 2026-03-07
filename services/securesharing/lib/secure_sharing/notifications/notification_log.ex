defmodule SecureSharing.Notifications.NotificationLog do
  @moduledoc """
  Schema for tracking sent notifications.

  Stores a history of all push notifications sent through the admin portal
  for auditing and debugging purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_logs" do
    field :title, :string
    field :body, :string
    field :notification_type, Ecto.Enum, values: [:broadcast, :targeted, :test]
    field :recipient_count, :integer, default: 0
    field :recipient_ids, {:array, :binary_id}, default: []
    field :data, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :sent, :failed], default: :pending
    field :error_message, :string
    field :onesignal_id, :string
    field :sent_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:title, :body, :notification_type, :sent_by_id]
  @optional_fields [
    :recipient_count,
    :recipient_ids,
    :data,
    :status,
    :error_message,
    :onesignal_id
  ]

  def changeset(log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, max: 200)
    |> validate_length(:body, max: 1000)
  end

  def mark_sent_changeset(log, onesignal_id) do
    log
    |> change(%{status: :sent, onesignal_id: onesignal_id})
  end

  def mark_failed_changeset(log, error_message) do
    log
    |> change(%{status: :failed, error_message: error_message})
  end
end
