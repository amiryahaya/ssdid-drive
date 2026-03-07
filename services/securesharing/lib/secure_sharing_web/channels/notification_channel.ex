defmodule SecureSharingWeb.NotificationChannel do
  @moduledoc """
  Channel for user notifications.

  Sends real-time notifications for:
  - New share invitations
  - Share revocations
  - Recovery requests (for trustees)
  - Recovery approvals (for owners)

  Topic format: "notification:{user_id}"

  ## Client Messages

  - `mark_read` - Mark a single notification as read
  - `mark_all_read` - Mark all notifications as read
  - `dismiss` - Dismiss a notification
  - `get_notifications` - Fetch paginated notifications
  - `get_unread_count` - Get unread notification count
  """

  use SecureSharingWeb, :channel

  alias SecureSharing.Notifications

  @impl true
  def join("notification:" <> user_id, _params, socket) do
    # Users can only join their own notification channel
    if socket.assigns.user_id == user_id do
      # Send initial unread count
      unread_count = Notifications.count_unread_notifications(user_id)
      {:ok, %{unread_count: unread_count}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("mark_read", %{"notification_id" => notification_id}, socket) do
    user_id = socket.assigns.user_id

    case Notifications.mark_notification_read(user_id, notification_id) do
      {:ok, notification} ->
        unread_count = Notifications.count_unread_notifications(user_id)
        {:reply, {:ok, %{notification_id: notification.id, unread_count: unread_count}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "notification_not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("mark_all_read", _params, socket) do
    user_id = socket.assigns.user_id
    {count, _} = Notifications.mark_all_notifications_read(user_id)
    {:reply, {:ok, %{marked_count: count, unread_count: 0}}, socket}
  end

  @impl true
  def handle_in("dismiss", %{"notification_id" => notification_id}, socket) do
    user_id = socket.assigns.user_id

    case Notifications.dismiss_notification(user_id, notification_id) do
      {:ok, notification} ->
        unread_count = Notifications.count_unread_notifications(user_id)
        {:reply, {:ok, %{notification_id: notification.id, unread_count: unread_count}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "notification_not_found"}}, socket}
    end
  end

  @impl true
  def handle_in("get_notifications", params, socket) do
    user_id = socket.assigns.user_id
    limit = Map.get(params, "limit", 50)
    offset = Map.get(params, "offset", 0)
    unread_only = Map.get(params, "unread_only", false)

    notifications =
      Notifications.list_user_notifications(user_id,
        limit: limit,
        offset: offset,
        unread_only: unread_only
      )

    data = Enum.map(notifications, &serialize_notification/1)
    {:reply, {:ok, %{notifications: data}}, socket}
  end

  @impl true
  def handle_in("get_unread_count", _params, socket) do
    user_id = socket.assigns.user_id
    count = Notifications.count_unread_notifications(user_id)
    {:reply, {:ok, %{unread_count: count}}, socket}
  end

  # ============================================================================
  # Broadcast helpers (called from other parts of the app)
  # ============================================================================

  @doc """
  Notify user of a new share invitation.
  """
  def broadcast_share_received(user_id, share) do
    payload = %{
      id: share.id,
      grantor_id: share.grantor_id,
      resource_type: share.resource_type,
      resource_id: share.resource_id,
      permission: share.permission,
      created_at: share.created_at
    }

    persist_and_broadcast(
      user_id,
      "share_received",
      "New Share",
      "Someone shared a #{share.resource_type} with you",
      payload
    )
  end

  @doc """
  Notify user of a revoked share.
  """
  def broadcast_share_revoked(user_id, share) do
    payload = %{
      id: share.id,
      resource_type: share.resource_type,
      resource_id: share.resource_id
    }

    persist_and_broadcast(
      user_id,
      "share_revoked",
      "Share Revoked",
      "A shared #{share.resource_type} was revoked",
      payload
    )
  end

  @doc """
  Notify trustee of a recovery request.
  """
  def broadcast_recovery_request(trustee_id, request) do
    payload = %{
      id: request.id,
      user_id: request.user_id,
      status: request.status,
      created_at: request.created_at,
      expires_at: request.expires_at
    }

    persist_and_broadcast(
      trustee_id,
      "recovery_request",
      "Recovery Request",
      "Someone needs your approval to recover their account",
      payload
    )
  end

  @doc """
  Notify owner of a recovery approval.
  """
  def broadcast_recovery_approval(owner_id, approval, progress) do
    payload = %{
      request_id: approval.request_id,
      trustee_id: approval.trustee_id,
      current_approvals: progress.current_approvals,
      threshold: progress.threshold,
      status: progress.status
    }

    persist_and_broadcast(
      owner_id,
      "recovery_approval",
      "Recovery Approved",
      "A trustee approved your recovery request (#{progress.current_approvals}/#{progress.threshold})",
      payload
    )
  end

  @doc """
  Notify owner that recovery is complete.
  """
  def broadcast_recovery_complete(owner_id, request) do
    payload = %{request_id: request.id}

    persist_and_broadcast(
      owner_id,
      "recovery_complete",
      "Recovery Complete",
      "Your account recovery is complete",
      payload
    )
  end

  @doc """
  Notify user of a tenant invitation.
  """
  def broadcast_tenant_invitation(user_id, tenant, inviter) do
    payload = %{
      tenant_id: tenant.id,
      tenant_name: tenant.name,
      inviter_id: inviter.id,
      inviter_name: inviter.display_name || inviter.email
    }

    persist_and_broadcast(
      user_id,
      "tenant_invitation",
      "Organization Invitation",
      "#{inviter.display_name || inviter.email} invited you to join #{tenant.name}",
      payload
    )
  end

  @doc """
  Generic notification broadcast with persistence.
  """
  def broadcast_notification(user_id, type, title, body, payload \\ %{}) do
    persist_and_broadcast(user_id, type, title, body, payload)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp persist_and_broadcast(user_id, type, title, body, payload) do
    # Persist the notification for read status tracking
    {:ok, notification} =
      Notifications.create_user_notification(user_id, %{
        type: type,
        title: title,
        body: body,
        data: payload
      })

    # Broadcast with the notification ID included
    broadcast_payload =
      Map.merge(payload, %{
        notification_id: notification.id,
        title: title,
        body: body,
        created_at: notification.inserted_at
      })

    SecureSharingWeb.Endpoint.broadcast("notification:#{user_id}", type, broadcast_payload)
  end

  defp serialize_notification(notification) do
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
