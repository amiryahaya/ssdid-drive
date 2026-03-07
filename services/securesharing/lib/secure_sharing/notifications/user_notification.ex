defmodule SecureSharing.Notifications.UserNotification do
  @moduledoc """
  Schema for tracking user notifications and their read status.

  This stores in-app notifications that are delivered via WebSocket channels
  and allows tracking whether users have read or dismissed them.

  ## Notification Types

  - `share_received` - When someone shares a file/folder with you
  - `share_revoked` - When a share is revoked
  - `recovery_request` - When a recovery request requires your approval
  - `recovery_approval` - When someone approves your recovery request
  - `recovery_complete` - When recovery is complete
  - `tenant_invitation` - When invited to join a tenant/organization
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_notifications" do
    field :type, :string
    field :title, :string
    field :body, :string
    field :data, :map, default: %{}
    field :read_at, :utc_datetime_usec
    field :dismissed_at, :utc_datetime_usec

    belongs_to :user, SecureSharing.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:user_id, :type, :title, :body]
  @optional_fields [:data, :read_at, :dismissed_at]

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, max: 200)
    |> validate_length(:body, max: 1000)
    |> foreign_key_constraint(:user_id)
  end

  def mark_read_changeset(notification) do
    change(notification, %{read_at: DateTime.utc_now()})
  end

  def mark_dismissed_changeset(notification) do
    change(notification, %{dismissed_at: DateTime.utc_now()})
  end
end
