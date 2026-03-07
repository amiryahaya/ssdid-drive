defmodule SecureSharing.Storage do
  @moduledoc """
  Unified blob storage operations for SecureSharing.

  This module provides a clean API for storing and retrieving encrypted file blobs.
  All blobs are encrypted client-side; the server never sees plaintext content.

  ## Configuration

      # config/config.exs (development)
      config :secure_sharing, SecureSharing.Storage,
        provider: SecureSharing.Storage.Providers.Local,
        base_path: "priv/storage"

      # config/runtime.exs (production)
      config :secure_sharing, SecureSharing.Storage,
        provider: SecureSharing.Storage.Providers.S3,
        bucket: System.get_env("S3_BUCKET"),
        region: System.get_env("AWS_REGION")

  ## Usage

      # Initialize storage (called at app startup)
      :ok = SecureSharing.Storage.init()

      # Generate presigned upload URL
      {:ok, url} = SecureSharing.Storage.presigned_upload_url("tenant/user/file")

      # Generate presigned download URL
      {:ok, url} = SecureSharing.Storage.presigned_download_url("tenant/user/file")

      # Direct upload (for server-side operations)
      {:ok, metadata} = SecureSharing.Storage.put("key", <<binary>>)

      # Direct download
      {:ok, binary} = SecureSharing.Storage.get("key")

      # Delete blob
      :ok = SecureSharing.Storage.delete("key")

  ## Storage Keys

  Keys follow the format: `{tenant_id}/{user_id}/{file_id}`
  This provides:
  - Natural partitioning by tenant
  - Easy access control alignment
  - Simple cleanup on tenant/user deletion
  """

  alias SecureSharing.Storage.Providers.Local

  require Logger

  @type key :: String.t()
  @type url :: String.t()

  @default_provider Local
  @upload_expiry_seconds 3600
  @download_expiry_seconds 900

  # Initialization

  @doc """
  Initialize the storage provider.

  Called during application startup. Validates configuration and
  establishes any necessary connections.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    provider = provider()
    config = config()

    Logger.info("Initializing storage provider: #{inspect(provider)}")

    case provider.init(config) do
      :ok ->
        Logger.info("Storage provider initialized successfully")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to initialize storage provider: #{inspect(reason)}")
        error
    end
  end

  # Configuration

  @doc """
  Get the configured storage provider module.
  """
  @spec provider() :: module()
  def provider do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Keyword.get(:provider, @default_provider)
  end

  @doc """
  Get the storage configuration as a map.
  """
  @spec config() :: map()
  def config do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Enum.into(%{})
  end

  # Public API

  @doc """
  Generate a presigned URL for uploading a blob.

  The client can PUT directly to this URL without authentication.

  ## Options

  - `:expires_in` - URL validity in seconds (default: #{@upload_expiry_seconds})
  - `:content_type` - Expected MIME type (default: "application/octet-stream")
  - `:content_length` - Expected size in bytes

  ## Examples

      {:ok, url} = Storage.presigned_upload_url("tenant123/user456/file789")
      {:ok, url} = Storage.presigned_upload_url("key", expires_in: 7200)
  """
  @spec presigned_upload_url(key(), keyword()) :: {:ok, url()} | {:error, term()}
  def presigned_upload_url(key, opts \\ []) when is_binary(key) do
    opts = Keyword.put_new(opts, :expires_in, @upload_expiry_seconds)
    provider().presigned_upload_url(key, opts)
  end

  @doc """
  Generate a presigned URL for downloading a blob.

  The client can GET directly from this URL without authentication.

  ## Options

  - `:expires_in` - URL validity in seconds (default: #{@download_expiry_seconds})

  ## Examples

      {:ok, url} = Storage.presigned_download_url("tenant123/user456/file789")
      {:ok, url} = Storage.presigned_download_url("key", expires_in: 300)
  """
  @spec presigned_download_url(key(), keyword()) :: {:ok, url()} | {:error, term()}
  def presigned_download_url(key, opts \\ []) when is_binary(key) do
    opts = Keyword.put_new(opts, :expires_in, @download_expiry_seconds)
    provider().presigned_download_url(key, opts)
  end

  @doc """
  Store a blob directly (for server-side operations).

  Prefer using presigned URLs for client uploads.

  ## Options

  - `:content_type` - MIME type (default: "application/octet-stream")

  ## Examples

      {:ok, metadata} = Storage.put("key", <<encrypted_data>>)
  """
  @spec put(key(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def put(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    provider().put_object(key, body, opts)
  end

  @doc """
  Retrieve a blob directly (for server-side operations).

  Prefer using presigned URLs for client downloads.

  ## Examples

      {:ok, data} = Storage.get("key")
  """
  @spec get(key()) :: {:ok, binary()} | {:error, term()}
  def get(key) when is_binary(key) do
    provider().get_object(key)
  end

  @doc """
  Delete a blob.

  Idempotent - deleting non-existent keys returns :ok.

  ## Examples

      :ok = Storage.delete("key")
  """
  @spec delete(key()) :: :ok | {:error, term()}
  def delete(key) when is_binary(key) do
    provider().delete_object(key)
  end

  @doc """
  Check if a blob exists at the given key.

  ## Examples

      true = Storage.exists?("key")
      false = Storage.exists?("nonexistent")
  """
  @spec exists?(key()) :: boolean()
  def exists?(key) when is_binary(key) do
    provider().object_exists?(key)
  end

  @doc """
  Get metadata about a stored blob.

  Returns size, content type, last modified, etc.

  ## Examples

      {:ok, %{size: 1024, content_type: "application/octet-stream"}} = Storage.head("key")
  """
  @spec head(key()) :: {:ok, map()} | {:error, term()}
  def head(key) when is_binary(key) do
    if function_exported?(provider(), :head_object, 1) do
      provider().head_object(key)
    else
      {:error, :not_supported}
    end
  end

  # Utility Functions

  @doc """
  Generate a storage key from tenant, user, and file IDs.

  ## Examples

      key = Storage.generate_key("tenant123", "user456", "file789")
      # => "tenant123/user456/file789"
  """
  @spec generate_key(String.t(), String.t(), String.t()) :: key()
  def generate_key(tenant_id, user_id, file_id) do
    "#{tenant_id}/#{user_id}/#{file_id}"
  end

  @doc """
  Parse a storage key into its components.

  ## Examples

      {:ok, {tenant_id, user_id, file_id}} = Storage.parse_key("t/u/f")
  """
  @spec parse_key(key()) :: {:ok, {String.t(), String.t(), String.t()}} | {:error, :invalid_key}
  def parse_key(key) when is_binary(key) do
    case String.split(key, "/") do
      [tenant_id, user_id, file_id] ->
        {:ok, {tenant_id, user_id, file_id}}

      _ ->
        {:error, :invalid_key}
    end
  end

  @doc """
  Get storage info for debugging/monitoring.
  """
  @spec info() :: map()
  def info do
    %{
      provider: provider(),
      config: config() |> Map.drop([:secret_access_key, :access_key_id]),
      upload_expiry_seconds: @upload_expiry_seconds,
      download_expiry_seconds: @download_expiry_seconds
    }
  end
end
