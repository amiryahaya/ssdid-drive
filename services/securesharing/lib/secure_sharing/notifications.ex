defmodule SecureSharing.Notifications do
  @moduledoc """
  The Notifications context for push notifications.

  Provides high-level functions for sending notifications for various app events.
  Uses OneSignal as the push notification provider for cross-platform support
  (Android, iOS, Windows).

  ## Notification Types

  - `:share_received` - When someone shares a file/folder with you
  - `:share_accepted` - When your share invitation is accepted
  - `:recovery_request` - When a recovery request requires your approval
  - `:recovery_approved` - When your recovery request is approved
  - `:recovery_denied` - When your recovery request is denied
  - `:device_enrolled` - When a new device is enrolled on your account
  - `:file_ready` - When a file download is ready

  ## Usage

      # Notify about new share
      Notifications.notify_share_received(recipient_user_id, %{
        from_name: "John Doe",
        item_name: "Project Files",
        share_id: "share-uuid"
      })

      # Notify trustees about recovery request
      Notifications.notify_recovery_request(trustee_ids, %{
        requester_name: "Jane Doe",
        request_id: "request-uuid"
      })
  """

  alias SecureSharing.Notifications.NotificationLog
  alias SecureSharing.Notifications.OneSignal
  alias SecureSharing.Notifications.UserNotification
  alias SecureSharing.Notifications.Worker
  alias SecureSharing.Repo

  import Ecto.Query

  require Logger

  # ============================================================================
  # Share Notifications
  # ============================================================================

  @doc """
  Notifies a user that someone shared a file/folder with them.
  """
  @spec notify_share_received(String.t(), map()) :: :ok | {:error, term()}
  def notify_share_received(user_id, params) do
    %{from_name: from_name, item_name: item_name} = params

    enqueue_notification(%{
      type: :share_received,
      user_ids: [user_id],
      title: "New Share",
      body: "#{from_name} shared \"#{truncate(item_name, 30)}\" with you",
      data: %{
        type: "share_received",
        share_id: params[:share_id]
      }
    })
  end

  @doc """
  Notifies a user that their share invitation was accepted.
  """
  @spec notify_share_accepted(String.t(), map()) :: :ok | {:error, term()}
  def notify_share_accepted(user_id, params) do
    %{recipient_name: recipient_name, item_name: item_name} = params

    enqueue_notification(%{
      type: :share_accepted,
      user_ids: [user_id],
      title: "Share Accepted",
      body: "#{recipient_name} accepted your share \"#{truncate(item_name, 30)}\"",
      data: %{
        type: "share_accepted",
        share_id: params[:share_id]
      }
    })
  end

  # ============================================================================
  # Recovery Notifications
  # ============================================================================

  @doc """
  Notifies trustees about a new recovery request that needs their approval.
  """
  @spec notify_recovery_request(list(String.t()), map()) :: :ok | {:error, term()}
  def notify_recovery_request(trustee_user_ids, params) when is_list(trustee_user_ids) do
    %{requester_name: requester_name} = params

    enqueue_notification(%{
      type: :recovery_request,
      user_ids: trustee_user_ids,
      title: "Recovery Request",
      body: "#{requester_name} is requesting account recovery and needs your approval",
      data: %{
        type: "recovery_request",
        request_id: params[:request_id]
      }
    })
  end

  @doc """
  Notifies a user that their recovery request was approved by a trustee.
  """
  @spec notify_recovery_approved(String.t(), map()) :: :ok | {:error, term()}
  def notify_recovery_approved(user_id, params) do
    %{trustee_name: trustee_name, shares_received: shares_received, threshold: threshold} = params

    enqueue_notification(%{
      type: :recovery_approved,
      user_ids: [user_id],
      title: "Recovery Approval",
      body: "#{trustee_name} approved your recovery request (#{shares_received}/#{threshold})",
      data: %{
        type: "recovery_approved",
        request_id: params[:request_id],
        shares_received: shares_received,
        threshold: threshold
      }
    })
  end

  @doc """
  Notifies a user that their recovery request was denied.
  """
  @spec notify_recovery_denied(String.t(), map()) :: :ok | {:error, term()}
  def notify_recovery_denied(user_id, params) do
    %{trustee_name: trustee_name} = params

    enqueue_notification(%{
      type: :recovery_denied,
      user_ids: [user_id],
      title: "Recovery Denied",
      body: "#{trustee_name} denied your recovery request",
      data: %{
        type: "recovery_denied",
        request_id: params[:request_id]
      }
    })
  end

  @doc """
  Notifies a user that their recovery is now complete and they can access their account.
  """
  @spec notify_recovery_complete(String.t(), map()) :: :ok | {:error, term()}
  def notify_recovery_complete(user_id, _params) do
    enqueue_notification(%{
      type: :recovery_complete,
      user_ids: [user_id],
      title: "Recovery Complete",
      body: "Your account recovery is complete. You can now log in.",
      data: %{
        type: "recovery_complete"
      }
    })
  end

  # ============================================================================
  # Device Notifications
  # ============================================================================

  @doc """
  Notifies a user that a new device was enrolled on their account.
  """
  @spec notify_device_enrolled(String.t(), map()) :: :ok | {:error, term()}
  def notify_device_enrolled(user_id, params) do
    %{device_name: device_name, platform: platform} = params

    enqueue_notification(%{
      type: :device_enrolled,
      user_ids: [user_id],
      title: "New Device",
      body: "A new #{platform} device \"#{device_name}\" was added to your account",
      data: %{
        type: "device_enrolled",
        device_id: params[:device_id]
      }
    })
  end

  # ============================================================================
  # File Notifications
  # ============================================================================

  @doc """
  Notifies a user that their file download/export is ready.
  """
  @spec notify_file_ready(String.t(), map()) :: :ok | {:error, term()}
  def notify_file_ready(user_id, params) do
    %{file_name: file_name} = params

    enqueue_notification(%{
      type: :file_ready,
      user_ids: [user_id],
      title: "Download Ready",
      body: "\"#{truncate(file_name, 30)}\" is ready to download",
      data: %{
        type: "file_ready",
        file_id: params[:file_id],
        download_url: params[:download_url]
      }
    })
  end

  # ============================================================================
  # Direct Send (for testing or immediate delivery)
  # ============================================================================

  @doc """
  Sends a notification immediately without using background job queue.

  Use this for testing or when you need guaranteed immediate delivery.
  For normal operation, use the specific notify_* functions which queue
  notifications for reliable delivery.
  """
  @spec send_now(map()) :: {:ok, map()} | {:error, term()}
  def send_now(opts) do
    OneSignal.send(opts)
  end

  @doc """
  Enqueues a notification, logging and swallowing any errors.

  Use this when notification failure should not affect the primary operation.
  """
  def enqueue_notification_safe(params) do
    case Worker.new(params) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to enqueue notification (non-critical): #{inspect(reason)}")
        :ok
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp enqueue_notification(params) do
    case Worker.new(params) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp truncate(string, max_length) when byte_size(string) <= max_length, do: string

  defp truncate(string, max_length) do
    String.slice(string, 0, max_length - 3) <> "..."
  end

  # ============================================================================
  # Admin Functions (for admin portal)
  # ============================================================================

  @doc """
  Sends a broadcast notification to all users.

  Returns the notification log record.
  """
  @spec broadcast_notification(map(), String.t()) :: {:ok, NotificationLog.t()} | {:error, term()}
  def broadcast_notification(attrs, sent_by_id) do
    log_attrs = %{
      title: attrs.title,
      body: attrs.body,
      notification_type: :broadcast,
      data: attrs[:data] || %{},
      sent_by_id: sent_by_id
    }

    case create_notification_log(log_attrs) do
      {:ok, log} ->
        case send_broadcast(attrs) do
          {:ok, response} ->
            update_notification_log(log, %{
              status: :sent,
              onesignal_id: response["id"],
              recipient_count: response["recipients"] || 0
            })

          {:error, reason} ->
            update_notification_log_error(log.id, inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a targeted notification to specific users.

  Returns the notification log record.
  """
  @spec send_targeted_notification(map(), list(String.t()), String.t()) ::
          {:ok, NotificationLog.t()} | {:error, term()}
  def send_targeted_notification(attrs, user_ids, sent_by_id) when is_list(user_ids) do
    log_attrs = %{
      title: attrs.title,
      body: attrs.body,
      notification_type: :targeted,
      recipient_ids: user_ids,
      recipient_count: length(user_ids),
      data: attrs[:data] || %{},
      sent_by_id: sent_by_id
    }

    with {:ok, log} <- create_notification_log(log_attrs),
         {:ok, response} <-
           OneSignal.send(%{
             user_ids: user_ids,
             title: attrs.title,
             body: attrs.body,
             data: attrs[:data] || %{}
           }) do
      update_notification_log(log, %{
        status: :sent,
        onesignal_id: response["id"]
      })
    else
      {:error, reason} = error ->
        Logger.error("Failed to send targeted notification: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Sends a test notification to a single user (the admin themselves).
  """
  @spec send_test_notification(map(), String.t()) :: {:ok, NotificationLog.t()} | {:error, term()}
  def send_test_notification(attrs, user_id) do
    log_attrs = %{
      title: attrs.title,
      body: attrs.body,
      notification_type: :test,
      recipient_ids: [user_id],
      recipient_count: 1,
      data: attrs[:data] || %{},
      sent_by_id: user_id
    }

    with {:ok, log} <- create_notification_log(log_attrs),
         {:ok, response} <-
           OneSignal.send(%{
             user_ids: [user_id],
             title: attrs.title,
             body: attrs.body,
             data: attrs[:data] || %{}
           }) do
      update_notification_log(log, %{
        status: :sent,
        onesignal_id: response["id"]
      })
    else
      {:error, reason} = error ->
        Logger.error("Failed to send test notification: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists notification logs with pagination.
  """
  @spec list_notification_logs(keyword()) :: [NotificationLog.t()]
  def list_notification_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    NotificationLog
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Gets a notification log by ID.
  """
  @spec get_notification_log(String.t()) :: NotificationLog.t() | nil
  def get_notification_log(id) do
    Repo.get(NotificationLog, id)
  end

  @doc """
  Counts total notification logs.
  """
  @spec count_notification_logs() :: integer()
  def count_notification_logs do
    Repo.aggregate(NotificationLog, :count, :id)
  end

  # Private admin helpers

  defp create_notification_log(attrs) do
    %NotificationLog{}
    |> NotificationLog.changeset(attrs)
    |> Repo.insert()
  end

  defp update_notification_log(log, attrs) do
    log
    |> NotificationLog.changeset(attrs)
    |> Repo.update()
  end

  defp update_notification_log_error(id, error_message) do
    case Repo.get(NotificationLog, id) do
      nil ->
        :ok

      log ->
        log
        |> NotificationLog.mark_failed_changeset(error_message)
        |> Repo.update()
    end
  end

  defp send_broadcast(attrs) do
    # OneSignal broadcast to all subscribed users
    # Using included_segments: ["Subscribed Users"] sends to all
    url = "https://onesignal.com/api/v1/notifications"

    payload = %{
      "app_id" => onesignal_app_id(),
      "included_segments" => ["Subscribed Users"],
      "headings" => %{"en" => attrs.title},
      "contents" => %{"en" => attrs.body}
    }

    payload = if attrs[:data], do: Map.put(payload, "data", attrs.data), else: payload

    case Req.post(url, json: payload, headers: onesignal_headers()) do
      {:ok, %Req.Response{status: 200, body: %{"id" => _} = response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("OneSignal broadcast failed: status=#{status}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OneSignal request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp onesignal_app_id do
    Application.get_env(:secure_sharing, SecureSharing.Notifications.OneSignal)[:app_id]
  end

  defp onesignal_headers do
    api_key =
      Application.get_env(:secure_sharing, SecureSharing.Notifications.OneSignal)[:api_key]

    [
      {"Authorization", "Basic #{api_key}"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]
  end

  # ============================================================================
  # User Notification Management (In-App Notifications)
  # ============================================================================

  @doc """
  Creates an in-app notification for a user.

  This is called when broadcasting notifications via WebSocket channels
  to persist the notification for read status tracking.
  """
  @spec create_user_notification(String.t(), map()) ::
          {:ok, UserNotification.t()} | {:error, Ecto.Changeset.t()}
  def create_user_notification(user_id, attrs) do
    %UserNotification{}
    |> UserNotification.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Gets a user notification by ID.
  """
  @spec get_user_notification(String.t()) :: UserNotification.t() | nil
  def get_user_notification(id) do
    Repo.get(UserNotification, id)
  end

  @doc """
  Gets a user notification by ID, ensuring it belongs to the user.
  """
  @spec get_user_notification(String.t(), String.t()) :: UserNotification.t() | nil
  def get_user_notification(user_id, notification_id) do
    UserNotification
    |> where([n], n.id == ^notification_id and n.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Lists notifications for a user with pagination.

  Options:
  - `:limit` - Maximum number of notifications to return (default: 50)
  - `:offset` - Number of notifications to skip (default: 0)
  - `:unread_only` - If true, only return unread notifications (default: false)
  """
  @spec list_user_notifications(String.t(), keyword()) :: [UserNotification.t()]
  def list_user_notifications(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    unread_only = Keyword.get(opts, :unread_only, false)

    query =
      UserNotification
      |> where([n], n.user_id == ^user_id)
      |> where([n], is_nil(n.dismissed_at))
      |> order_by([n], desc: n.inserted_at)
      |> limit(^limit)
      |> offset(^offset)

    query =
      if unread_only do
        where(query, [n], is_nil(n.read_at))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts unread notifications for a user.
  """
  @spec count_unread_notifications(String.t()) :: integer()
  def count_unread_notifications(user_id) do
    UserNotification
    |> where([n], n.user_id == ^user_id)
    |> where([n], is_nil(n.read_at))
    |> where([n], is_nil(n.dismissed_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Marks a notification as read.
  """
  @spec mark_notification_read(String.t(), String.t()) ::
          {:ok, UserNotification.t()} | {:error, :not_found}
  def mark_notification_read(user_id, notification_id) do
    case get_user_notification(user_id, notification_id) do
      nil ->
        {:error, :not_found}

      %UserNotification{read_at: nil} = notification ->
        notification
        |> UserNotification.mark_read_changeset()
        |> Repo.update()

      notification ->
        {:ok, notification}
    end
  end

  @doc """
  Marks all notifications as read for a user.
  """
  @spec mark_all_notifications_read(String.t()) :: {integer(), nil}
  def mark_all_notifications_read(user_id) do
    now = DateTime.utc_now()

    UserNotification
    |> where([n], n.user_id == ^user_id)
    |> where([n], is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now])
  end

  @doc """
  Dismisses a notification (removes from list without marking as read).
  """
  @spec dismiss_notification(String.t(), String.t()) ::
          {:ok, UserNotification.t()} | {:error, :not_found}
  def dismiss_notification(user_id, notification_id) do
    case get_user_notification(user_id, notification_id) do
      nil ->
        {:error, :not_found}

      %UserNotification{dismissed_at: nil} = notification ->
        notification
        |> UserNotification.mark_dismissed_changeset()
        |> Repo.update()

      notification ->
        {:ok, notification}
    end
  end

  @doc """
  Deletes old notifications that have been read or dismissed.

  This can be called from a cleanup job to keep the table size manageable.
  """
  @spec cleanup_old_notifications(integer()) :: {integer(), nil}
  def cleanup_old_notifications(days_old \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -days_old, :day)

    UserNotification
    |> where([n], not is_nil(n.read_at) or not is_nil(n.dismissed_at))
    |> where([n], n.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end
end
