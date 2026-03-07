defmodule SecureSharing.Storage.BlobStore do
  @moduledoc """
  Behaviour definition for blob storage providers.

  Implementations handle storing and retrieving encrypted file blobs.
  The server never sees plaintext content - all blobs are encrypted client-side.

  ## Implementations

  - `SecureSharing.Storage.Providers.Local` - Local filesystem (dev/test)
  - `SecureSharing.Storage.Providers.S3` - AWS S3 or S3-compatible storage

  ## Storage Keys

  Keys follow the pattern: `{tenant_id}/{user_id}/{file_id}`
  This provides natural partitioning and access control alignment.
  """

  @type key :: String.t()
  @type url :: String.t()
  @type config :: map()

  @doc """
  Initialize the storage provider with configuration.

  Called once at application startup. Should validate configuration
  and establish any necessary connections.
  """
  @callback init(config()) :: :ok | {:error, term()}

  @doc """
  Store a blob at the given key.

  Options:
  - `:content_type` - MIME type (default: "application/octet-stream")
  - `:content_length` - Size in bytes (required for some providers)

  Returns `{:ok, metadata}` where metadata includes storage details.
  """
  @callback put_object(key(), body :: binary(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Retrieve a blob by key.

  Returns the raw binary content of the blob.
  """
  @callback get_object(key()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Delete a blob by key.

  Should be idempotent - deleting non-existent keys returns :ok.
  """
  @callback delete_object(key()) :: :ok | {:error, term()}

  @doc """
  Generate a presigned URL for uploading a blob.

  Options:
  - `:expires_in` - URL validity in seconds (default: 3600)
  - `:content_type` - Expected MIME type
  - `:content_length` - Expected size in bytes

  The returned URL allows direct upload without authentication.
  """
  @callback presigned_upload_url(key(), opts :: keyword()) ::
              {:ok, url()} | {:error, term()}

  @doc """
  Generate a presigned URL for downloading a blob.

  Options:
  - `:expires_in` - URL validity in seconds (default: 900)

  The returned URL allows direct download without authentication.
  """
  @callback presigned_download_url(key(), opts :: keyword()) ::
              {:ok, url()} | {:error, term()}

  @doc """
  Check if a blob exists at the given key.
  """
  @callback object_exists?(key()) :: boolean()

  @doc """
  Get metadata about a stored blob.

  Returns size, content type, last modified, etc.
  """
  @callback head_object(key()) :: {:ok, map()} | {:error, term()}

  @doc """
  Clean up resources. Called on application shutdown.
  """
  @callback cleanup() :: :ok

  # Optional callbacks with defaults
  @optional_callbacks [cleanup: 0, head_object: 1]
end
