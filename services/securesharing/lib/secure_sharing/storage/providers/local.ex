defmodule SecureSharing.Storage.Providers.Local do
  @moduledoc """
  Local filesystem blob storage provider.

  Stores blobs on the local filesystem. Intended for development and testing.
  NOT recommended for production use.

  ## Configuration

      config :secure_sharing, SecureSharing.Storage,
        provider: SecureSharing.Storage.Providers.Local,
        base_path: "priv/storage"

  ## Storage Layout

  Blobs are stored at: `{base_path}/{key}`
  Where key follows: `{tenant_id}/{user_id}/{file_id}`

  ## Presigned URLs

  For local development, presigned URLs point to a mock endpoint.
  The actual upload/download happens through the local filesystem.
  """

  @behaviour SecureSharing.Storage.BlobStore

  require Logger

  @default_base_path "priv/storage"
  @default_upload_expiry 3600
  @default_download_expiry 900

  # State stored in process dictionary for simplicity
  # In production, this would be in a GenServer or ETS

  @impl true
  def init(config) do
    base_path = Map.get(config, :base_path, @default_base_path)

    case File.mkdir_p(base_path) do
      :ok ->
        Process.put(:local_storage_base_path, base_path)
        Logger.info("Local storage initialized at #{base_path}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to initialize local storage at #{base_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def put_object(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    path = full_path(key)

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, body) do
      metadata = %{
        key: key,
        size: byte_size(body),
        content_type: Keyword.get(opts, :content_type, "application/octet-stream"),
        etag: :crypto.hash(:md5, body) |> Base.encode16(case: :lower),
        last_modified: DateTime.utc_now()
      }

      {:ok, metadata}
    else
      {:error, reason} ->
        Logger.error("Failed to write blob #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_object(key) when is_binary(key) do
    path = full_path(key)

    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to read blob #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete_object(key) when is_binary(key) do
    path = full_path(key)

    case File.rm(path) do
      :ok ->
        cleanup_empty_dirs(path)
        :ok

      {:error, :enoent} ->
        # Idempotent - deleting non-existent is ok
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete blob #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def presigned_upload_url(key, opts \\ []) when is_binary(key) do
    expires_in = Keyword.get(opts, :expires_in, @default_upload_expiry)
    expires_at = System.system_time(:second) + expires_in

    # Generate a signed token for local upload
    token = generate_token(key, :upload, expires_at)

    # URL for local development - points to a local endpoint
    # In a real setup, this would be handled by a Phoenix endpoint
    base_url = get_local_base_url()
    url = "#{base_url}/storage/upload/#{URI.encode(key)}?token=#{token}&expires=#{expires_at}"

    {:ok, url}
  end

  @impl true
  def presigned_download_url(key, opts \\ []) when is_binary(key) do
    expires_in = Keyword.get(opts, :expires_in, @default_download_expiry)
    expires_at = System.system_time(:second) + expires_in

    # Generate a signed token for local download
    token = generate_token(key, :download, expires_at)

    base_url = get_local_base_url()
    url = "#{base_url}/storage/download/#{URI.encode(key)}?token=#{token}&expires=#{expires_at}"

    {:ok, url}
  end

  @impl true
  def object_exists?(key) when is_binary(key) do
    path = full_path(key)
    File.exists?(path)
  end

  @impl true
  def head_object(key) when is_binary(key) do
    path = full_path(key)

    case File.stat(path) do
      {:ok, stat} ->
        {:ok,
         %{
           key: key,
           size: stat.size,
           last_modified:
             stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC"),
           content_type: "application/octet-stream"
         }}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def cleanup do
    :ok
  end

  # Private functions

  defp base_path do
    Process.get(:local_storage_base_path, @default_base_path)
  end

  defp full_path(key) do
    Path.join(base_path(), key)
  end

  defp ensure_directory(file_path) do
    dir = Path.dirname(file_path)
    File.mkdir_p(dir)
  end

  defp cleanup_empty_dirs(file_path) do
    # Clean up empty parent directories up to base_path
    dir = Path.dirname(file_path)
    base = base_path()

    if dir != base and String.starts_with?(dir, base) do
      case File.rmdir(dir) do
        :ok -> cleanup_empty_dirs(dir)
        _ -> :ok
      end
    end
  end

  defp generate_token(key, operation, expires_at) do
    secret = Application.get_env(:secure_sharing, :storage_secret, "local_dev_secret")
    data = "#{key}:#{operation}:#{expires_at}"
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.url_encode64(padding: false)
  end

  defp get_local_base_url do
    # Get the configured endpoint URL or use a default
    host =
      Application.get_env(:secure_sharing, SecureSharingWeb.Endpoint)[:url][:host] || "localhost"

    port = Application.get_env(:secure_sharing, SecureSharingWeb.Endpoint)[:http][:port] || 4000
    "http://#{host}:#{port}"
  end

  # Public functions for validating presigned URLs (used by upload/download endpoints)

  @doc """
  Verify a presigned URL token.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  def verify_token(key, operation, token, expires_at) do
    now = System.system_time(:second)

    cond do
      expires_at < now ->
        {:error, :expired}

      token != generate_token(key, operation, expires_at) ->
        {:error, :invalid_token}

      true ->
        :ok
    end
  end
end
