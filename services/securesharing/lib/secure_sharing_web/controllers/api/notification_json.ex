defmodule SecureSharingWeb.API.NotificationJSON do
  @moduledoc """
  JSON rendering for notification responses.
  """

  alias SecureSharing.Notifications.UserNotification

  def index(%{notifications: notifications, unread_count: unread_count}) do
    %{
      data: Enum.map(notifications, &notification_data/1),
      meta: %{
        unread_count: unread_count
      }
    }
  end

  defp notification_data(%UserNotification{} = notification) do
    %{
      id: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      data: notification.data,
      read_at: notification.read_at,
      created_at: notification.inserted_at
    }
  end
end
