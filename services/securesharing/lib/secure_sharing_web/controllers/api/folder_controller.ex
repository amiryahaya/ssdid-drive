defmodule SecureSharingWeb.API.FolderController do
  @moduledoc """
  Controller for folder operations.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Files
  alias SecureSharing.Repo
  alias SecureSharing.Sharing

  action_fallback SecureSharingWeb.FallbackController

  plug SecureSharingWeb.Plugs.Audit,
       [resource_type: "folder"]
       when action in [:show, :create, :update, :delete, :move, :transfer_ownership]

  @doc """
  Get the user's root folder.

  GET /api/folders/root

  Returns the root folder if it exists, or null if not.
  To create a root folder, use POST /api/folders with is_root: true.
  """
  def root(conn, _params) do
    user = conn.assigns.current_user

    case Files.get_root_folder(user) |> preload_owner() do
      nil ->
        render(conn, :show, folder: nil)

      folder ->
        render(conn, :show, folder: folder)
    end
  end

  @doc """
  List all folders owned by the user.

  GET /api/folders

  Query params:
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)
  """
  def index(conn, params) do
    user = conn.assigns.current_user
    pagination = SecureSharingWeb.Helpers.PaginationHelpers.parse_pagination(params)

    folders =
      user
      |> Files.list_user_folders(pagination)
      |> Repo.preload(:owner)

    total_count = Files.count_user_folders(user)

    meta =
      SecureSharingWeb.Helpers.PaginationHelpers.build_pagination_meta(
        folders,
        pagination,
        total_count
      )

    render(conn, :index, folders: folders, meta: meta)
  end

  @doc """
  Get a specific folder.

  GET /api/folders/:id
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, folder} <- get_folder(id),
         true <- Sharing.has_folder_access?(user, folder) do
      render(conn, :show, folder: folder)
    end
  end

  @doc """
  Create a new folder.

  POST /api/folders

  Request body for root folder:
  ```json
  {
    "is_root": true,
    "encrypted_metadata": "base64...",
    "wrapped_kek": "base64...",
    "kem_ciphertext": "base64...",
    "owner_wrapped_kek": "base64...",
    "owner_kem_ciphertext": "base64..."
  }
  ```

  Request body for subfolder:
  ```json
  {
    "parent_id": "uuid",
    "encrypted_metadata": "base64...",
    "wrapped_kek": "base64...",
    "kem_ciphertext": "base64...",
    "owner_wrapped_kek": "base64...",
    "owner_kem_ciphertext": "base64..."
  }
  ```
  """
  def create(conn, %{"is_root" => true} = params) do
    user = conn.assigns.current_user

    with %{} = attrs <- decode_folder_params(params),
         {:ok, folder} <- Files.create_root_folder(user, attrs) do
      conn
      |> put_status(:created)
      |> render(:show, folder: Repo.preload(folder, :owner))
    end
  end

  def create(conn, %{"parent_id" => parent_id} = params) do
    user = conn.assigns.current_user

    with %{} = attrs <- decode_folder_params(params),
         {:ok, parent} <- get_folder(parent_id),
         true <- Sharing.can_write_folder?(user, parent),
         {:ok, folder} <- Files.create_folder(parent, user, attrs) do
      conn
      |> put_status(:created)
      |> render(:show, folder: Repo.preload(folder, :owner))
    end
  end

  @doc """
  Update folder metadata.

  PUT /api/folders/:id

  Request body:
  ```json
  {
    "encrypted_metadata": "base64..."
  }
  ```
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with %{} = attrs <- decode_folder_params(params),
         {:ok, folder} <- get_folder(id),
         true <- Sharing.can_write_folder?(user, folder),
         {:ok, updated} <-
           Files.update_folder_metadata(folder, Map.put(attrs, :updated_by_id, user.id)) do
      render(conn, :show, folder: Repo.preload(updated, :owner))
    end
  end

  @doc """
  Move folder to different parent.

  POST /api/folders/:id/move

  Request body:
  ```json
  {
    "parent_id": "new_parent_uuid",
    "wrapped_kek": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64..."
  }
  ```
  """
  def move(conn, %{"id" => id, "parent_id" => parent_id} = params) do
    user = conn.assigns.current_user

    with %{} = attrs <- decode_folder_params(params),
         {:ok, folder} <- get_folder(id),
         true <- Sharing.can_write_folder?(user, folder),
         {:ok, new_parent} <- get_folder(parent_id),
         {:ok, moved} <- Files.move_folder(folder, new_parent, user, attrs) do
      render(conn, :show, folder: Repo.preload(moved, :owner))
    end
  end

  @doc """
  Delete a folder.

  DELETE /api/folders/:id

  Cannot delete root folders.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, folder} <- get_folder(id),
         true <- Sharing.can_delete_folder?(user, folder),
         {:ok, _} <- Files.delete_folder(folder) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  List child folders.

  GET /api/folders/:folder_id/children

  Query params:
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)
  """
  def children(conn, %{"folder_id" => folder_id} = params) do
    user = conn.assigns.current_user
    pagination = SecureSharingWeb.Helpers.PaginationHelpers.parse_pagination(params)

    with {:ok, folder} <- get_folder(folder_id),
         true <- Sharing.has_folder_access?(user, folder) do
      children =
        folder
        |> Files.list_child_folders(pagination)
        |> Repo.preload(:owner)

      total_count = Files.count_child_folders(folder)

      meta =
        SecureSharingWeb.Helpers.PaginationHelpers.build_pagination_meta(
          children,
          pagination,
          total_count
        )

      render(conn, :index, folders: children, meta: meta)
    end
  end

  @doc """
  Transfer folder ownership to another user.

  POST /api/folders/:id/transfer-ownership

  Request body:
  ```json
  {
    "new_owner_id": "uuid",
    "wrapped_kek": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64...",
    "old_owner_wrapped_key": "base64...",
    "old_owner_kem_ciphertext": "base64...",
    "old_owner_signature": "base64..."
  }
  ```
  """
  def transfer_ownership(conn, %{"id" => id, "new_owner_id" => new_owner_id} = params) do
    user = conn.assigns.current_user
    attrs = decode_transfer_params(params)

    with {:ok, folder} <- get_folder(id),
         {:ok, new_owner} <- get_user(new_owner_id),
         {:ok, updated_folder} <-
           Sharing.transfer_folder_ownership(folder, user, new_owner, attrs) do
      render(conn, :show, folder: Repo.preload(updated_folder, :owner))
    end
  end

  # Private functions

  defp get_user(id) do
    case SecureSharing.Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp get_folder(id) do
    case Files.get_folder(id, [:owner]) do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

  defp preload_owner(nil), do: nil
  defp preload_owner(folder), do: Repo.preload(folder, :owner)

  defp decode_folder_params(params) do
    alias SecureSharingWeb.Helpers.BinaryHelpers

    binary_fields = [
      :encrypted_metadata,
      :metadata_nonce,
      :wrapped_kek,
      :kem_ciphertext,
      :owner_wrapped_kek,
      :owner_kem_ciphertext,
      :signature
    ]

    case BinaryHelpers.decode_fields(params, binary_fields) do
      {:ok, decoded} -> decoded
      {:error, {:invalid_base64, field}} -> {:error, {:invalid_base64, field}}
    end
  end

  defp decode_transfer_params(params) do
    alias SecureSharingWeb.Helpers.BinaryHelpers

    %{}
    |> maybe_put(:wrapped_kek, BinaryHelpers.decode_base64_optional(params["wrapped_kek"]))
    |> maybe_put(:kem_ciphertext, BinaryHelpers.decode_base64_optional(params["kem_ciphertext"]))
    |> maybe_put(:signature, BinaryHelpers.decode_base64_optional(params["signature"]))
    |> maybe_put(
      :old_owner_wrapped_key,
      BinaryHelpers.decode_base64_optional(params["old_owner_wrapped_key"])
    )
    |> maybe_put(
      :old_owner_kem_ciphertext,
      BinaryHelpers.decode_base64_optional(params["old_owner_kem_ciphertext"])
    )
    |> maybe_put(
      :old_owner_signature,
      BinaryHelpers.decode_base64_optional(params["old_owner_signature"])
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
