defmodule SecureSharingWeb.API.NotificationController do
  @moduledoc """
  Controller for notification management.

  Provides REST API endpoints for:
  - Listing notifications
  - Marking notifications as read
  - Getting unread count

  These endpoints complement the WebSocket channel for clients
  that need to sync notifications on app startup or when offline.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Notifications

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  List notifications for the current user.

  GET /api/notifications

  Query parameters:
  - limit: Maximum number of notifications (default: 50)
  - offset: Pagination offset (default: 0)
  - unread_only: If "true", only return unread notifications

  Response:
  ```json
  {
    "data": [
      {
        "id": "uuid",
        "type": "share_received",
        "title": "New Share",
        "body": "Someone shared a file with you",
        "data": {...},
        "read_at": null,
        "created_at": "2024-01-01T00:00:00Z"
      }
    ],
    "meta": {
      "unread_count": 5
    }
  }
  ```
  """
  def index(conn, params) do
    user_id = conn.assigns[:user_id]
    limit = parse_int(params["limit"], 50)
    offset = parse_int(params["offset"], 0)
    unread_only = params["unread_only"] == "true"

    notifications =
      Notifications.list_user_notifications(user_id,
        limit: limit,
        offset: offset,
        unread_only: unread_only
      )

    unread_count = Notifications.count_unread_notifications(user_id)

    render(conn, :index, notifications: notifications, unread_count: unread_count)
  end

  @doc """
  Get unread notification count.

  GET /api/notifications/unread_count

  Response:
  ```json
  {
    "data": {
      "unread_count": 5
    }
  }
  ```
  """
  def unread_count(conn, _params) do
    user_id = conn.assigns[:user_id]
    count = Notifications.count_unread_notifications(user_id)

    json(conn, %{data: %{unread_count: count}})
  end

  @doc """
  Mark a notification as read.

  POST /api/notifications/:id/read

  Response:
  ```json
  {
    "data": {
      "notification_id": "uuid",
      "unread_count": 4
    }
  }
  ```
  """
  def mark_read(conn, %{"id" => notification_id}) do
    user_id = conn.assigns[:user_id]

    case Notifications.mark_notification_read(user_id, notification_id) do
      {:ok, notification} ->
        unread_count = Notifications.count_unread_notifications(user_id)
        json(conn, %{data: %{notification_id: notification.id, unread_count: unread_count}})

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Mark all notifications as read.

  POST /api/notifications/read_all

  Response:
  ```json
  {
    "data": {
      "marked_count": 5,
      "unread_count": 0
    }
  }
  ```
  """
  def mark_all_read(conn, _params) do
    user_id = conn.assigns[:user_id]
    {count, _} = Notifications.mark_all_notifications_read(user_id)

    json(conn, %{data: %{marked_count: count, unread_count: 0}})
  end

  @doc """
  Dismiss a notification.

  DELETE /api/notifications/:id

  Response: 204 No Content
  """
  def delete(conn, %{"id" => notification_id}) do
    user_id = conn.assigns[:user_id]

    case Notifications.dismiss_notification(user_id, notification_id) do
      {:ok, _notification} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
end
