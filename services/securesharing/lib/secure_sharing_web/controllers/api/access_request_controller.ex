defmodule SecureSharingWeb.API.AccessRequestController do
  @moduledoc """
  Controller for share permission upgrade requests.

  Allows grantees to request higher permissions (e.g., `:read` → `:write`)
  from the share grantor or resource owner/admin.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Sharing

  action_fallback SecureSharingWeb.FallbackController

  plug SecureSharingWeb.Plugs.Audit,
       [resource_type: "access_request"]
       when action in [:request_upgrade, :approve, :deny]

  @doc """
  Request a permission upgrade on a share.

  POST /api/shares/:id/request-upgrade

  Request body:
  ```json
  {
    "requested_permission": "write",
    "reason": "I need to edit the document"
  }
  ```
  """
  def request_upgrade(conn, %{"id" => share_id} = params) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(share_id),
         requested_permission <- parse_permission(params["requested_permission"]),
         attrs <- %{requested_permission: requested_permission, reason: params["reason"]},
         {:ok, request} <- Sharing.request_upgrade(share, user, attrs) do
      # Notify the grantor about the upgrade request
      notify_upgrade_request(share, user, request)

      conn
      |> put_status(:created)
      |> render(:show, access_request: request)
    end
  end

  @doc """
  Approve a pending upgrade request.

  POST /api/shares/:share_id/approve-upgrade

  Request body:
  ```json
  {
    "request_id": "uuid",
    "signature": "base64..."
  }
  ```
  """
  def approve(conn, %{"id" => share_id} = params) do
    user = conn.assigns.current_user

    with {:ok, _share} <- get_share(share_id),
         {:ok, request} <- get_pending_request(params["request_id"]),
         :ok <- verify_request_for_share(request, share_id),
         attrs <- %{signature: decode_binary(params["signature"])},
         {:ok, result} <- Sharing.approve_upgrade(request, user, attrs) do
      # Notify the requester that their request was approved
      notify_upgrade_approved(result.share, result.request)

      render(conn, :show, access_request: result.request)
    end
  end

  @doc """
  Deny a pending upgrade request.

  POST /api/shares/:share_id/deny-upgrade

  Request body:
  ```json
  {
    "request_id": "uuid"
  }
  ```
  """
  def deny(conn, %{"id" => share_id} = params) do
    user = conn.assigns.current_user

    with {:ok, _share} <- get_share(share_id),
         {:ok, request} <- get_pending_request(params["request_id"]),
         :ok <- verify_request_for_share(request, share_id),
         {:ok, updated_request} <- Sharing.deny_upgrade(request, user) do
      render(conn, :show, access_request: updated_request)
    end
  end

  @doc """
  List pending upgrade requests for shares the current user has created.

  GET /api/shares/upgrade-requests
  """
  def pending(conn, _params) do
    user = conn.assigns.current_user
    requests = Sharing.list_pending_requests_for_grantor(user)
    render(conn, :index, access_requests: requests)
  end

  @doc """
  List upgrade requests made by the current user.

  GET /api/shares/my-upgrade-requests
  """
  def my_requests(conn, _params) do
    user = conn.assigns.current_user
    requests = Sharing.list_requests_by_requester(user)
    render(conn, :index, access_requests: requests)
  end

  # Private

  defp get_share(id) do
    case Sharing.get_share_grant(id) do
      nil -> {:error, :not_found}
      share -> {:ok, share}
    end
  end

  defp get_pending_request(nil), do: {:error, {:bad_request, "Missing required field: request_id"}}

  defp get_pending_request(id) do
    case Sharing.get_access_request(id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  end

  defp verify_request_for_share(request, share_id) do
    if request.share_grant_id == share_id do
      :ok
    else
      {:error, :not_found}
    end
  end

  defp parse_permission("write"), do: :write
  defp parse_permission("admin"), do: :admin
  defp parse_permission(_), do: nil

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64_optional(data)
  end

  defp notify_upgrade_request(share, requester, _request) do
    SecureSharing.Notifications.enqueue_notification_safe(%{
      type: :access_upgrade_requested,
      user_ids: [share.grantor_id],
      title: "Permission Upgrade Request",
      body: "#{requester.email} requested upgraded access",
      data: %{share_id: share.id}
    })
  end

  defp notify_upgrade_approved(share, request) do
    SecureSharing.Notifications.enqueue_notification_safe(%{
      type: :access_upgrade_approved,
      user_ids: [request.requester_id],
      title: "Permission Upgraded",
      body: "Your access was upgraded to #{request.requested_permission}",
      data: %{share_id: share.id}
    })
  end
end
