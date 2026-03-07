defmodule SecureSharing.StorageTest do
  use ExUnit.Case, async: false

  alias SecureSharing.Storage

  @test_storage_path "tmp/test_storage"

  setup do
    # Clean up test storage before each test
    File.rm_rf!(@test_storage_path)
    File.mkdir_p!(@test_storage_path)

    # Initialize storage
    :ok = Storage.init()

    on_exit(fn ->
      File.rm_rf!(@test_storage_path)
    end)

    :ok
  end

  describe "configuration" do
    test "provider returns the configured provider module" do
      assert Storage.provider() == SecureSharing.Storage.Providers.Local
    end

    test "config returns storage configuration" do
      config = Storage.config()
      assert config[:provider] == SecureSharing.Storage.Providers.Local
      assert config[:base_path] == @test_storage_path
    end

    test "info returns storage information" do
      info = Storage.info()
      assert info.provider == SecureSharing.Storage.Providers.Local
      assert is_integer(info.upload_expiry_seconds)
      assert is_integer(info.download_expiry_seconds)
    end
  end

  describe "put/get operations" do
    test "put stores a blob" do
      key = "tenant1/user1/file1"
      data = "test content"

      {:ok, metadata} = Storage.put(key, data)

      assert metadata.key == key
      assert metadata.size == byte_size(data)
    end

    test "get retrieves a stored blob" do
      key = "tenant1/user1/file2"
      data = "test content for get"

      {:ok, _} = Storage.put(key, data)
      {:ok, retrieved} = Storage.get(key)

      assert retrieved == data
    end

    test "get returns error for non-existent key" do
      {:error, :not_found} = Storage.get("nonexistent/key")
    end

    test "put/get round-trip with binary data" do
      key = "tenant1/user1/binary_file"
      data = :crypto.strong_rand_bytes(1024)

      {:ok, _} = Storage.put(key, data)
      {:ok, retrieved} = Storage.get(key)

      assert retrieved == data
    end
  end

  describe "delete operations" do
    test "delete removes a blob" do
      key = "tenant1/user1/to_delete"
      data = "data to delete"

      {:ok, _} = Storage.put(key, data)
      assert Storage.exists?(key)

      :ok = Storage.delete(key)
      refute Storage.exists?(key)
    end

    test "delete is idempotent" do
      key = "tenant1/user1/nonexistent"

      # Deleting non-existent key should succeed
      :ok = Storage.delete(key)
      :ok = Storage.delete(key)
    end
  end

  describe "exists? operation" do
    test "exists? returns true for existing blob" do
      key = "tenant1/user1/exists_test"
      {:ok, _} = Storage.put(key, "test")

      assert Storage.exists?(key)
    end

    test "exists? returns false for non-existent blob" do
      refute Storage.exists?("nonexistent/blob")
    end

    test "exists? can verify blob before marking upload complete (blob verification)" do
      # This tests the blob verification feature for file uploads
      # When a client claims upload is complete, we verify the blob exists

      storage_path = "tenant1/user1/#{UUIDv7.generate()}"

      # Before upload, blob doesn't exist
      refute Storage.exists?(storage_path)

      # Simulate file upload
      {:ok, _} = Storage.put(storage_path, :crypto.strong_rand_bytes(1024))

      # After upload, blob should exist
      assert Storage.exists?(storage_path)

      # This verification prevents orphan database records where
      # the file metadata exists but the blob was never uploaded
    end

    test "exists? returns false for deleted blob" do
      key = "tenant1/user1/deleted_blob"
      {:ok, _} = Storage.put(key, "data")
      assert Storage.exists?(key)

      :ok = Storage.delete(key)
      refute Storage.exists?(key)
    end
  end

  describe "head operation" do
    test "head returns metadata for existing blob" do
      key = "tenant1/user1/head_test"
      data = "head test data"
      {:ok, _} = Storage.put(key, data)

      {:ok, metadata} = Storage.head(key)

      assert metadata.key == key
      assert metadata.size == byte_size(data)
    end

    test "head returns error for non-existent blob" do
      {:error, :not_found} = Storage.head("nonexistent/key")
    end
  end

  describe "presigned URLs" do
    test "presigned_upload_url generates a URL" do
      key = "tenant1/user1/upload_test"

      {:ok, url} = Storage.presigned_upload_url(key)

      assert is_binary(url)
      assert String.contains?(url, key)
    end

    test "presigned_upload_url accepts options" do
      key = "tenant1/user1/upload_with_opts"

      {:ok, url} = Storage.presigned_upload_url(key, expires_in: 7200)

      assert is_binary(url)
    end

    test "presigned_download_url generates a URL" do
      key = "tenant1/user1/download_test"
      {:ok, _} = Storage.put(key, "test data")

      {:ok, url} = Storage.presigned_download_url(key)

      assert is_binary(url)
      assert String.contains?(url, key)
    end

    test "presigned_download_url accepts options" do
      key = "tenant1/user1/download_with_opts"

      {:ok, url} = Storage.presigned_download_url(key, expires_in: 300)

      assert is_binary(url)
    end
  end

  describe "utility functions" do
    test "generate_key creates proper key format" do
      key = Storage.generate_key("tenant123", "user456", "file789")

      assert key == "tenant123/user456/file789"
    end

    test "parse_key extracts components" do
      {:ok, {tenant_id, user_id, file_id}} = Storage.parse_key("tenant123/user456/file789")

      assert tenant_id == "tenant123"
      assert user_id == "user456"
      assert file_id == "file789"
    end

    test "parse_key returns error for invalid key" do
      {:error, :invalid_key} = Storage.parse_key("invalid_key")
      {:error, :invalid_key} = Storage.parse_key("only/two")
      {:error, :invalid_key} = Storage.parse_key("too/many/parts/here")
    end
  end

  describe "nested directories" do
    test "put creates nested directories" do
      key = "deep/nested/path/file"
      {:ok, _} = Storage.put(key, "nested data")

      assert Storage.exists?(key)
      {:ok, data} = Storage.get(key)
      assert data == "nested data"
    end

    test "delete cleans up empty parent directories" do
      key = "cleanup/test/nested/file"
      {:ok, _} = Storage.put(key, "data")
      :ok = Storage.delete(key)

      # The directories should be cleaned up
      refute File.exists?(Path.join(@test_storage_path, "cleanup/test/nested"))
    end
  end
end
