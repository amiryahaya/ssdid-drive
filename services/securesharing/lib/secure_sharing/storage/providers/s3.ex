defmodule SecureSharing.Storage.Providers.S3 do
  @moduledoc """
  AWS S3 blob storage provider.

  Uses ExAws for S3 operations. Supports AWS S3 and S3-compatible
  services (MinIO, Garage, etc.).

  ## Configuration

      # config/runtime.exs
      config :secure_sharing, SecureSharing.Storage,
        provider: SecureSharing.Storage.Providers.S3,
        bucket: System.get_env("S3_BUCKET"),
        region: System.get_env("AWS_REGION", "us-east-1")

      config :ex_aws,
        access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
        region: System.get_env("AWS_REGION", "us-east-1")

      # For S3-compatible services (MinIO, Garage)
      config :ex_aws, :s3,
        scheme: "http://",
        host: "localhost",
        port: 3900

  ## Storage Layout

  Blobs are stored at: `s3://{bucket}/{key}`
  Where key follows: `{tenant_id}/{user_id}/{file_id}`
  """

  @behaviour SecureSharing.Storage.BlobStore

  require Logger

  @default_upload_expiry 3600
  @default_download_expiry 900
  @content_type "application/octet-stream"

  @impl true
  def init(config) do
    bucket = Map.get(config, :bucket)
    region = Map.get(config, :region, "us-east-1")

    if is_nil(bucket) or bucket == "" do
      {:error, :bucket_not_configured}
    else
      # Store config in application env for this provider
      Application.put_env(:secure_sharing, __MODULE__, %{
        bucket: bucket,
        region: region
      })

      Logger.info("S3 storage initialized for bucket: #{bucket} in region: #{region}")
      :ok
    end
  end

  @impl true
  def put_object(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    bucket = get_bucket()
    content_type = Keyword.get(opts, :content_type, @content_type)

    request =
      ExAws.S3.put_object(bucket, key, body, content_type: content_type)

    case ExAws.request(request) do
      {:ok, %{status_code: 200, headers: headers}} ->
        etag =
          headers
          |> Enum.find(fn {k, _} -> String.downcase(k) == "etag" end)
          |> case do
            {_, v} -> String.trim(v, "\"")
            nil -> nil
          end

        {:ok,
         %{
           key: key,
           bucket: bucket,
           size: byte_size(body),
           content_type: content_type,
           etag: etag,
           last_modified: DateTime.utc_now()
         }}

      {:ok, %{status_code: status}} ->
        Logger.error("S3 put_object failed with status #{status} for key: #{key}")
        {:error, :upload_failed}

      {:error, reason} ->
        Logger.error("S3 put_object error for key #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_object(key) when is_binary(key) do
    bucket = get_bucket()
    request = ExAws.S3.get_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        Logger.error("S3 get_object failed with status #{status} for key: #{key}")
        {:error, :download_failed}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("S3 get_object error for key #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete_object(key) when is_binary(key) do
    bucket = get_bucket()
    request = ExAws.S3.delete_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        :ok

      {:ok, %{status_code: 404}} ->
        # Idempotent - deleting non-existent is ok
        :ok

      {:ok, %{status_code: status}} ->
        Logger.error("S3 delete_object failed with status #{status} for key: #{key}")
        {:error, :delete_failed}

      {:error, {:http_error, 404, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("S3 delete_object error for key #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def presigned_upload_url(key, opts \\ []) when is_binary(key) do
    bucket = get_bucket()
    expires_in = Keyword.get(opts, :expires_in, @default_upload_expiry)

    # ExAws presign for PUT operation
    presign_opts = [
      expires_in: expires_in,
      virtual_host: false
    ]

    config = ExAws.Config.new(:s3)

    url =
      ExAws.S3.presigned_url(
        config,
        :put,
        bucket,
        key,
        presign_opts
      )

    case url do
      {:ok, presigned_url} ->
        {:ok, presigned_url}

      {:error, reason} ->
        Logger.error("Failed to generate presigned upload URL for key #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def presigned_download_url(key, opts \\ []) when is_binary(key) do
    bucket = get_bucket()
    expires_in = Keyword.get(opts, :expires_in, @default_download_expiry)

    presign_opts = [
      expires_in: expires_in,
      virtual_host: false
    ]

    config = ExAws.Config.new(:s3)

    url =
      ExAws.S3.presigned_url(
        config,
        :get,
        bucket,
        key,
        presign_opts
      )

    case url do
      {:ok, presigned_url} ->
        {:ok, presigned_url}

      {:error, reason} ->
        Logger.error(
          "Failed to generate presigned download URL for key #{key}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @impl true
  def object_exists?(key) when is_binary(key) do
    case head_object(key) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def head_object(key) when is_binary(key) do
    bucket = get_bucket()
    request = ExAws.S3.head_object(bucket, key)

    case ExAws.request(request) do
      {:ok, %{status_code: 200, headers: headers}} ->
        metadata = parse_head_headers(key, headers)
        {:ok, metadata}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("S3 head_object error for key #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def cleanup do
    :ok
  end

  # Private functions

  defp get_bucket do
    config = Application.get_env(:secure_sharing, __MODULE__, %{})
    Map.get(config, :bucket)
  end

  defp parse_head_headers(key, headers) do
    headers_map =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
      |> Map.new()

    %{
      key: key,
      size: parse_content_length(headers_map["content-length"]),
      content_type: headers_map["content-type"] || @content_type,
      etag: headers_map["etag"] |> String.trim("\""),
      last_modified: parse_last_modified(headers_map["last-modified"])
    }
  end

  defp parse_content_length(nil), do: 0

  defp parse_content_length(value) when is_binary(value) do
    case Integer.parse(value) do
      {size, _} -> size
      :error -> 0
    end
  end

  defp parse_last_modified(nil), do: nil

  defp parse_last_modified(value) when is_binary(value) do
    # RFC1123 format: "Sun, 06 Nov 1994 08:49:37 GMT"
    # Use :httpd_util.convert_request_date for parsing HTTP dates
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      :bad_date ->
        nil

      {{year, month, day}, {hour, min, sec}} ->
        case NaiveDateTime.new(year, month, day, hour, min, sec) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end
end
