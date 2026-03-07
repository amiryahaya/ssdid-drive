defmodule SecureSharing.Storage.Providers.S3Test do
  @moduledoc """
  Tests for the S3 blob storage provider.

  These tests mock ExAws to avoid requiring actual S3 connections.
  """

  use ExUnit.Case, async: false

  alias SecureSharing.Storage.Providers.S3

  setup do
    # Store original config to restore later
    original_ex_aws_config = Application.get_env(:ex_aws, :s3)

    # Configure mock AWS credentials for presigned URL generation
    # These are fake credentials that allow ExAws to generate presigned URLs
    # without trying to fetch real credentials from instance metadata
    Application.put_env(:ex_aws, :access_key_id, "AKIAIOSFODNN7EXAMPLE")
    Application.put_env(:ex_aws, :secret_access_key, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    Application.put_env(:ex_aws, :region, "us-east-1")

    # Configure S3 specific settings
    Application.put_env(:ex_aws, :s3,
      scheme: "https://",
      host: "s3.amazonaws.com",
      region: "us-east-1"
    )

    # Configure the S3 provider with test bucket
    Application.put_env(:secure_sharing, S3, %{
      bucket: "test-bucket",
      region: "us-east-1"
    })

    on_exit(fn ->
      Application.delete_env(:secure_sharing, S3)
      Application.delete_env(:ex_aws, :access_key_id)
      Application.delete_env(:ex_aws, :secret_access_key)

      if original_ex_aws_config do
        Application.put_env(:ex_aws, :s3, original_ex_aws_config)
      else
        Application.delete_env(:ex_aws, :s3)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "returns :ok when bucket is configured" do
      config = %{bucket: "my-bucket", region: "us-west-2"}

      assert :ok = S3.init(config)

      stored = Application.get_env(:secure_sharing, S3)
      assert stored.bucket == "my-bucket"
      assert stored.region == "us-west-2"
    end

    test "uses default region when not specified" do
      config = %{bucket: "my-bucket"}

      assert :ok = S3.init(config)

      stored = Application.get_env(:secure_sharing, S3)
      assert stored.region == "us-east-1"
    end

    test "returns error when bucket is nil" do
      config = %{bucket: nil}

      assert {:error, :bucket_not_configured} = S3.init(config)
    end

    test "returns error when bucket is empty string" do
      config = %{bucket: ""}

      assert {:error, :bucket_not_configured} = S3.init(config)
    end

    test "returns error when bucket is not provided" do
      config = %{}

      assert {:error, :bucket_not_configured} = S3.init(config)
    end
  end

  describe "presigned_upload_url/2" do
    test "generates presigned upload URL" do
      key = "tenant1/user1/file1"

      {:ok, url} = S3.presigned_upload_url(key)

      assert is_binary(url)
      assert String.contains?(url, key)
      assert String.contains?(url, "X-Amz-Signature")
    end

    test "accepts custom expiration" do
      key = "tenant1/user1/file1"

      {:ok, url} = S3.presigned_upload_url(key, expires_in: 7200)

      assert is_binary(url)
    end
  end

  describe "presigned_download_url/2" do
    test "generates presigned download URL" do
      key = "tenant1/user1/file1"

      {:ok, url} = S3.presigned_download_url(key)

      assert is_binary(url)
      assert String.contains?(url, key)
      assert String.contains?(url, "X-Amz-Signature")
    end

    test "accepts custom expiration" do
      key = "tenant1/user1/file1"

      {:ok, url} = S3.presigned_download_url(key, expires_in: 1800)

      assert is_binary(url)
    end
  end

  describe "cleanup/0" do
    test "returns :ok" do
      assert :ok = S3.cleanup()
    end
  end
end
