defmodule SecureSharingWeb.API.FileController do
  @moduledoc """
  Controller for file operations.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Files
  alias SecureSharing.Sharing
  alias SecureSharing.Storage
  alias SecureSharing.Storage.Workers.BlobCleanupWorker

  action_fallback SecureSharingWeb.FallbackController

  plug SecureSharingWeb.Plugs.Audit,
       [resource_type: "file"]
       when action in [
              :show,
              :update,
              :delete,
              :upload_url,
              :download_url,
              :move,
              :transfer_ownership
            ]

  @doc """
  List all files accessible to the current user (owned + shared).

  GET /api/files/accessible

  Returns all files the user owns plus files shared with them via active
  share grants. Clients use this for local search since the server cannot
  search encrypted metadata (zero-knowledge).

  Query params:
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)
  - status: Filter by file status (e.g., "complete")
  """
  def accessible(conn, params) do
    user = conn.assigns.current_user
    pagination = SecureSharingWeb.Helpers.PaginationHelpers.parse_pagination(params)
    status_filter = params["status"]

    {files, total_count} = Files.list_accessible_files(user, pagination, status: status_filter)

    meta =
      SecureSharingWeb.Helpers.PaginationHelpers.build_pagination_meta(
        files,
        pagination,
        total_count
      )

    render(conn, :index, files: files, meta: meta)
  end

  @doc """
  List files in a folder.

  GET /api/folders/:folder_id/files

  Query params:
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)
  """
  def index(conn, %{"folder_id" => folder_id} = params) do
    user = conn.assigns.current_user
    pagination = SecureSharingWeb.Helpers.PaginationHelpers.parse_pagination(params)

    with {:ok, folder} <- get_folder(folder_id),
         true <- Sharing.has_folder_access?(user, folder) do
      files = Files.list_folder_files(folder, pagination)
      total_count = Files.count_folder_files(folder)

      meta =
        SecureSharingWeb.Helpers.PaginationHelpers.build_pagination_meta(
          files,
          pagination,
          total_count
        )

      render(conn, :index, files: files, meta: meta)
    end
  end

  @doc """
  Get file metadata.

  GET /api/files/:id
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, file} <- get_file(id),
         true <- Sharing.has_file_access?(user, file) do
      render(conn, :show, file: file)
    end
  end

  @doc """
  Create file and get presigned upload URL.

  POST /api/files/upload-url

  Request body:
  ```json
  {
    "folder_id": "uuid",
    "blob_size": 1024000,
    "encrypted_metadata": "base64...",
    "wrapped_dek": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64..."
  }
  ```
  """
  def upload_url(conn, %{"folder_id" => folder_id} = params) do
    user = conn.assigns.current_user
    tenant_id = conn.assigns.tenant_id
    blob_size = params["blob_size"] || params["size"] || 0

    with {:ok, folder} <- get_folder(folder_id),
         true <- Sharing.can_write_folder?(user, folder),
         :ok <- check_quota(tenant_id, blob_size),
         %{} = attrs <- decode_file_params(params) do
      storage_path = generate_storage_path(user)
      attrs = Map.put(attrs, :storage_path, storage_path)
      # For root folder uploads (folder=nil), use tenant_id from JWT
      attrs = if is_nil(folder), do: Map.put(attrs, :tenant_id, tenant_id), else: attrs

      with {:ok, file} <- Files.create_file(folder, user, attrs),
           {:ok, upload_url} <- generate_presigned_upload_url(storage_path, blob_size) do
        conn
        |> put_status(:created)
        |> render(:upload_url, file: file, upload_url: upload_url)
      end
    end
  end

  @doc """
  Get presigned download URL.

  GET /api/files/:id/download-url
  """
  def download_url(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, file} <- get_file(id),
         true <- Sharing.has_file_access?(user, file),
         {:ok, url} <- generate_presigned_download_url(file.storage_path) do
      render(conn, :download_url, file: file, download_url: url)
    end
  end

  @doc """
  Update file status (after upload completion).

  PUT /api/files/:id

  Request body:
  ```json
  {
    "status": "complete",
    "blob_hash": "sha256..."
  }
  ```

  When marking status as "complete", verifies the blob actually exists in storage
  to prevent orphan database records.
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    attrs = Map.take(params, ["status", "blob_hash", "blob_size", "chunk_count"])

    with {:ok, file} <- get_file(id),
         true <- Sharing.can_write_file?(user, file),
         :ok <- maybe_verify_blob_exists(file, attrs),
         {:ok, updated} <-
           Files.update_file_status(file, Map.put(attrs, "updated_by_id", user.id)) do
      render(conn, :show, file: updated)
    end
  end

  @doc """
  Move file to different folder.

  POST /api/files/:id/move

  Request body:
  ```json
  {
    "folder_id": "new_folder_uuid",
    "wrapped_dek": "base64...",
    "kem_ciphertext": "base64...",
    "signature": "base64..."
  }
  ```
  """
  def move(conn, %{"id" => id, "folder_id" => new_folder_id} = params) do
    user = conn.assigns.current_user

    with %{} = attrs <- decode_file_params(params),
         {:ok, file} <- get_file(id),
         true <- Sharing.can_write_file?(user, file),
         {:ok, new_folder} <- get_folder(new_folder_id),
         {:ok, moved} <- Files.move_file(file, new_folder, user, attrs) do
      render(conn, :show, file: moved)
    end
  end

  @doc """
  Delete a file.

  DELETE /api/files/:id
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, file} <- get_file(id),
         true <- Sharing.can_delete_file?(user, file),
         storage_path <- file.storage_path,
         {:ok, _} <- Files.delete_file(file) do
      # Schedule blob deletion in background
      BlobCleanupWorker.schedule_deletion(storage_path)
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Transfer file ownership to another user.

  POST /api/files/:id/transfer-ownership

  Request body:
  ```json
  {
    "new_owner_id": "uuid",
    "wrapped_dek": "base64...",
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

    with {:ok, file} <- get_file(id),
         {:ok, new_owner} <- get_user(new_owner_id),
         {:ok, updated_file} <- Sharing.transfer_file_ownership(file, user, new_owner, attrs) do
      render(conn, :show, file: updated_file)
    end
  end

  # Private functions

  defp get_user(id) do
    with :ok <- validate_uuid(id) do
      case SecureSharing.Accounts.get_user(id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end
  end

  defp get_file(id) do
    with :ok <- validate_uuid(id) do
      case Files.get_file(id) do
        nil -> {:error, :not_found}
        file -> {:ok, file}
      end
    end
  end

  # Handle nil folder_id for root folder uploads
  defp get_folder(nil), do: {:ok, nil}

  defp get_folder(id) do
    with :ok <- validate_uuid(id) do
      case Files.get_folder(id) do
        nil -> {:error, :not_found}
        folder -> {:ok, folder}
      end
    end
  end

  # Validate UUID format to prevent crashes and injection attempts
  defp validate_uuid(id) do
    case SecureSharing.InputSanitizer.validate_uuid(id) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :invalid_uuid}
    end
  end

  # Verify blob exists in storage when marking status as "complete"
  # This prevents orphan database records for uploads that never completed
  defp maybe_verify_blob_exists(file, %{"status" => "complete"}) do
    if Storage.exists?(file.storage_path) do
      :ok
    else
      {:error, :blob_not_found}
    end
  end

  defp maybe_verify_blob_exists(_file, _attrs), do: :ok

  defp check_quota(tenant_id, size) do
    if Files.has_storage_quota_by_tenant?(tenant_id, size) do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  defp generate_storage_path(user) do
    file_id = Ecto.UUID.generate()
    "#{user.tenant_id}/#{user.id}/#{file_id}"
  end

  defp generate_presigned_upload_url(storage_path, size) do
    opts = if size > 0, do: [content_length: size], else: []
    Storage.presigned_upload_url(storage_path, opts)
  end

  defp generate_presigned_download_url(storage_path) do
    Storage.presigned_download_url(storage_path)
  end

  defp decode_file_params(params) do
    alias SecureSharingWeb.Helpers.BinaryHelpers

    binary_fields = [:encrypted_metadata, :wrapped_dek, :kem_ciphertext, :signature]

    case BinaryHelpers.decode_fields(params, binary_fields) do
      {:ok, decoded} ->
        decoded
        |> maybe_put(:blob_size, params["blob_size"])

      {:error, {:invalid_base64, field}} ->
        # Return error tuple to be handled by the action
        {:error, {:invalid_base64, field}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_transfer_params(params) do
    alias SecureSharingWeb.Helpers.BinaryHelpers

    %{}
    |> maybe_put(:wrapped_dek, BinaryHelpers.decode_base64_optional(params["wrapped_dek"]))
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
end
