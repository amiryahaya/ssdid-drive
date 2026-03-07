defmodule SecureSharingWeb.API.RecoveryController do
  @moduledoc """
  Controller for recovery operations.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts
  alias SecureSharing.Recovery

  action_fallback SecureSharingWeb.FallbackController

  plug SecureSharingWeb.Plugs.Audit, [resource_type: "recovery_config"] when action in [:setup]

  plug SecureSharingWeb.Plugs.Audit,
       [resource_type: "recovery_request"] when action in [:create_request, :approve, :complete]

  # === Recovery Configuration ===

  @doc """
  Get current user's recovery configuration.

  GET /api/recovery/config
  """
  def show_config(conn, _params) do
    user = conn.assigns.current_user
    config = Recovery.get_recovery_config(user)
    render(conn, :config, config: config)
  end

  @doc """
  Setup recovery for current user.

  POST /api/recovery/setup

  Request body:
  ```json
  {
    "threshold": 3,
    "total_shares": 5
  }
  ```
  """
  def setup(conn, params) do
    user = conn.assigns.current_user

    case Recovery.get_recovery_config(user) do
      nil ->
        with {:ok, config} <- Recovery.setup_recovery(user, params) do
          conn
          |> put_status(:created)
          |> render(:config, config: config)
        end

      _existing ->
        {:error, :config_exists}
    end
  end

  # === Recovery Shares (Trustee Distribution) ===

  @doc """
  Create a recovery share for a trustee.

  POST /api/recovery/shares

  Request body:
  ```json
  {
    "trustee_id": "uuid",
    "share_index": 1,
    "encrypted_share": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64..."
  }
  ```
  """
  def create_share(conn, %{"trustee_id" => trustee_id} = params) do
    user = conn.assigns.current_user
    attrs = decode_share_params(params)

    with {:ok, config} <- get_recovery_config(user),
         {:ok, trustee} <- get_user(trustee_id),
         :ok <- verify_same_tenant(user, trustee),
         {:ok, share} <- Recovery.create_share(config, user, trustee, attrs) do
      conn
      |> put_status(:created)
      |> render(:share, share: share)
    end
  end

  @doc """
  List shares where current user is the trustee.

  GET /api/recovery/shares/trustee
  """
  def trustee_shares(conn, _params) do
    user = conn.assigns.current_user
    shares = Recovery.list_trustee_shares(user)
    render(conn, :shares, shares: shares)
  end

  @doc """
  List shares where current user is the owner (grantor).

  GET /api/recovery/shares/created
  """
  def owner_shares(conn, _params) do
    user = conn.assigns.current_user
    shares = Recovery.list_owner_shares(user)
    render(conn, :shares, shares: shares)
  end

  @doc """
  Accept a recovery share (as trustee).

  POST /api/recovery/shares/:id/accept
  """
  def accept_share(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_trustee(user, share),
         {:ok, accepted} <- Recovery.accept_share(share) do
      render(conn, :share, share: accepted)
    end
  end

  @doc """
  Reject a recovery share (as trustee).

  POST /api/recovery/shares/:id/reject
  """
  def reject_share(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_trustee(user, share),
         {:ok, _rejected} <- Recovery.reject_share(share) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Revoke a recovery share (as grantor/owner).

  DELETE /api/recovery/shares/:id
  """
  def revoke_share(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_grantor(user, share),
         {:ok, _deleted} <- Recovery.revoke_share(share) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Disable recovery for the current user.

  DELETE /api/recovery/config
  """
  def disable(conn, _params) do
    user = conn.assigns.current_user

    case Recovery.disable_recovery(user) do
      {:ok, :ok} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # === Recovery Requests ===

  @doc """
  Create a recovery request.

  POST /api/recovery/request

  Request body:
  ```json
  {
    "new_public_key": "base64...",
    "reason": "Lost device"
  }
  ```
  """
  def create_request(conn, params) do
    user = conn.assigns.current_user

    with {:ok, new_public_key} <- decode_required_binary(params["new_public_key"]),
         {:ok, request} <-
           Recovery.create_recovery_request(user, new_public_key, reason: params["reason"]) do
      conn
      |> put_status(:created)
      |> render(:request, request: request)
    end
  end

  @doc """
  List recovery requests for current user.

  GET /api/recovery/requests
  """
  def list_requests(conn, _params) do
    user = conn.assigns.current_user
    requests = Recovery.list_user_requests(user)
    render(conn, :requests, requests: requests)
  end

  @doc """
  List pending recovery requests where current user is a trustee.

  GET /api/recovery/requests/pending
  """
  def pending_for_trustee(conn, _params) do
    user = conn.assigns.current_user
    requests = Recovery.list_pending_requests_for_trustee(user)
    render(conn, :requests, requests: requests)
  end

  @doc """
  Get a specific recovery request with progress.

  GET /api/recovery/requests/:id
  """
  def show_request(conn, %{"id" => id}) do
    with {:ok, request} <- get_request(id) do
      progress = Recovery.get_recovery_progress(request)
      render(conn, :request_detail, request: request, progress: progress)
    end
  end

  @doc """
  Approve a recovery request (as trustee).

  POST /api/recovery/requests/:id/approve

  Request body:
  ```json
  {
    "share_id": "uuid",
    "reencrypted_share": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64..."
  }
  ```
  """
  def approve(conn, %{"id" => id, "share_id" => share_id} = params) do
    user = conn.assigns.current_user
    attrs = decode_approval_params(params)

    with {:ok, request} <- get_request(id),
         {:ok, share} <- get_share(share_id),
         :ok <- verify_trustee(user, share),
         {:ok, approval} <- Recovery.approve_recovery(request, share, user, attrs) do
      conn
      |> put_status(:created)
      |> render(:approval, approval: approval)
    end
  end

  @doc """
  Complete recovery and update key material.

  POST /api/recovery/requests/:id/complete

  Request body:
  ```json
  {
    "encrypted_master_key": "base64...",
    "encrypted_private_keys": "base64...",
    "key_derivation_salt": "base64...",
    "public_keys": {"kem": "base64...", "sign": "base64..."}
  }
  ```
  """
  def complete(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    new_key_material = decode_key_material(params)

    alias SecureSharing.Workers.EmailWorker

    with {:ok, request} <- get_request(id),
         :ok <- verify_request_owner(user, request),
         true <- Recovery.threshold_reached?(request),
         {:ok, updated_user} <- Recovery.finalize_recovery(user, request, new_key_material) do
      # Send recovery complete email via Oban with retry logic
      EmailWorker.enqueue_recovery_complete(updated_user)

      render(conn, :complete, user: updated_user)
    else
      false -> {:error, :threshold_not_reached}
      error -> error
    end
  end

  @doc """
  Cancel a pending recovery request.

  DELETE /api/recovery/requests/:id
  """
  def cancel(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, request} <- get_request(id),
         :ok <- verify_request_owner(user, request),
         {:ok, _deleted} <- Recovery.cancel_request(request) do
      send_resp(conn, :no_content, "")
    end
  end

  # Private functions

  defp get_recovery_config(user) do
    case Recovery.get_recovery_config(user) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  defp get_user(id) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp get_share(id) do
    case Recovery.get_share(id) do
      nil -> {:error, :not_found}
      share -> {:ok, share}
    end
  end

  defp get_request(id) do
    case Recovery.get_recovery_request(id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  end

  defp verify_same_tenant(user, trustee) do
    if user.tenant_id == trustee.tenant_id do
      :ok
    else
      {:error, :cross_tenant_share}
    end
  end

  defp verify_trustee(user, share) do
    if share.trustee_id == user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp verify_grantor(user, share) do
    if share.grantor_id == user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp verify_request_owner(user, request) do
    if request.user_id == user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp decode_share_params(params) do
    %{}
    |> maybe_put(:share_index, params["share_index"])
    |> maybe_put(:encrypted_share, decode_binary(params["encrypted_share"]))
    |> maybe_put(:kem_ciphertext, decode_binary(params["kem_ciphertext"]))
    |> maybe_put(:signature, decode_binary(params["signature"]))
  end

  defp decode_approval_params(params) do
    %{}
    |> maybe_put(:reencrypted_share, decode_binary(params["reencrypted_share"]))
    |> maybe_put(:kem_ciphertext, decode_binary(params["kem_ciphertext"]))
    |> maybe_put(:signature, decode_binary(params["signature"]))
  end

  defp decode_key_material(params) do
    %{}
    |> maybe_put(:encrypted_master_key, decode_binary(params["encrypted_master_key"]))
    |> maybe_put(:encrypted_private_keys, decode_binary(params["encrypted_private_keys"]))
    |> maybe_put(:key_derivation_salt, decode_binary(params["key_derivation_salt"]))
    |> maybe_put(:public_keys, params["public_keys"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64_optional(data)
  end

  defp decode_required_binary(nil), do: {:error, :missing_required_field}

  defp decode_required_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64(data)
  end
end
