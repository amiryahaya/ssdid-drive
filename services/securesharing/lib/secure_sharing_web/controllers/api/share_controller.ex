defmodule SecureSharingWeb.API.ShareController do
  @moduledoc """
  Controller for share management.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts
  alias SecureSharing.Files
  alias SecureSharing.Sharing

  action_fallback SecureSharingWeb.FallbackController

  plug SecureSharingWeb.Plugs.Audit,
       [resource_type: "share"]
       when action in [
              :show,
              :share_file,
              :share_folder,
              :update_permission,
              :set_expiry,
              :revoke
            ]

  @doc """
  List shares received by current user.

  GET /api/shares/received
  """
  def received(conn, _params) do
    user = conn.assigns.current_user
    shares = Sharing.list_received_shares(user)
    render(conn, :index, shares: shares)
  end

  @doc """
  List shares created by current user.

  GET /api/shares/created
  """
  def created(conn, _params) do
    user = conn.assigns.current_user
    shares = Sharing.list_created_shares(user)
    render(conn, :index, shares: shares)
  end

  @doc """
  Get a specific share.

  GET /api/shares/:id
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_share_access(user, share) do
      render(conn, :show, share: share)
    end
  end

  @doc """
  Share a file with another user.

  POST /api/shares/file

  Request body:
  ```json
  {
    "file_id": "uuid",
    "grantee_id": "uuid",
    "wrapped_key": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64...",
    "permission": "read",
    "expires_at": "2024-12-31T23:59:59Z"
  }
  ```
  """
  def share_file(conn, %{"file_id" => file_id, "grantee_id" => grantee_id} = params) do
    user = conn.assigns.current_user
    attrs = decode_share_params(params)

    with {:ok, file} <- get_file(file_id),
         true <- Sharing.can_share_file?(user, file),
         {:ok, grantee} <- get_user(grantee_id),
         :ok <- verify_same_tenant(user, grantee),
         {:ok, share} <- Sharing.share_file(file, user, grantee, attrs) do
      conn
      |> put_status(:created)
      |> render(:show, share: share)
    end
  end

  @doc """
  Share a folder with another user.

  POST /api/shares/folder

  Request body:
  ```json
  {
    "folder_id": "uuid",
    "grantee_id": "uuid",
    "wrapped_key": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64...",
    "permission": "read",
    "recursive": true,
    "expires_at": "2024-12-31T23:59:59Z"
  }
  ```
  """
  def share_folder(conn, %{"folder_id" => folder_id, "grantee_id" => grantee_id} = params) do
    user = conn.assigns.current_user
    attrs = decode_share_params(params)

    with {:ok, folder} <- get_folder(folder_id),
         true <- Sharing.can_share_folder?(user, folder),
         {:ok, grantee} <- get_user(grantee_id),
         :ok <- verify_same_tenant(user, grantee),
         {:ok, share} <- Sharing.share_folder(folder, user, grantee, attrs) do
      conn
      |> put_status(:created)
      |> render(:show, share: share)
    end
  end

  @doc """
  Update share permission level.

  PUT /api/shares/:id/permission

  Request body:
  ```json
  {
    "permission": "write",
    "signature": "base64..."
  }
  ```
  """
  def update_permission(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    attrs = decode_share_params(params)

    with {:ok, share} <- get_share(id),
         :ok <- verify_grantor(user, share),
         {:ok, updated} <- Sharing.update_permission(share, attrs) do
      render(conn, :show, share: updated)
    end
  end

  @doc """
  Set or update share expiry.

  PUT /api/shares/:id/expiry

  Request body:
  ```json
  {
    "expires_at": "2024-12-31T23:59:59Z"
  }
  ```

  Or to remove expiry:
  ```json
  {
    "expires_at": null
  }
  ```
  """
  def set_expiry(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_grantor(user, share) do
      result =
        case params["expires_at"] do
          nil -> Sharing.remove_expiry(share)
          expires_at -> update_expiry(share, expires_at)
        end

      case result do
        {:ok, updated} -> render(conn, :show, share: updated)
        error -> error
      end
    end
  end

  @doc """
  Revoke a share.

  DELETE /api/shares/:id
  """
  def revoke(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, share} <- get_share(id),
         :ok <- verify_grantor(user, share),
         {:ok, _} <- Sharing.revoke_share(share, user) do
      send_resp(conn, :no_content, "")
    end
  end

  # Private functions

  defp get_share(id) do
    case Sharing.get_share_grant(id) do
      nil -> {:error, :not_found}
      share -> {:ok, share}
    end
  end

  defp get_file(id) do
    case Files.get_file(id) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  defp get_folder(id) do
    case Files.get_folder(id) do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

  defp get_user(id) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp verify_share_access(user, share) do
    if share.grantor_id == user.id or share.grantee_id == user.id do
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

  defp verify_same_tenant(user, grantee) do
    if user.tenant_id == grantee.tenant_id do
      :ok
    else
      {:error, :cross_tenant_share}
    end
  end

  defp update_expiry(share, expires_at_string) do
    case DateTime.from_iso8601(expires_at_string) do
      {:ok, expires_at, _offset} -> Sharing.set_expiry(share, expires_at)
      {:error, _} -> {:error, :invalid_datetime}
    end
  end

  defp decode_share_params(params) do
    %{}
    |> maybe_put(:wrapped_key, decode_binary(params["wrapped_key"]))
    |> maybe_put(:kem_ciphertext, decode_binary(params["kem_ciphertext"]))
    |> maybe_put(:signature, decode_binary(params["signature"]))
    |> maybe_put(:permission, parse_permission(params["permission"]))
    |> maybe_put(:recursive, params["recursive"])
    |> maybe_put(:expires_at, parse_datetime(params["expires_at"]))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64_optional(data)
  end

  defp parse_permission(nil), do: nil
  defp parse_permission("read"), do: :read
  defp parse_permission("write"), do: :write
  defp parse_permission("admin"), do: :admin
  defp parse_permission(_), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end
end
