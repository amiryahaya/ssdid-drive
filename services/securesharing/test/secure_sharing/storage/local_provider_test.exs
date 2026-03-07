defmodule SecureSharing.Storage.Providers.LocalTest do
  use ExUnit.Case, async: false

  alias SecureSharing.Storage.Providers.Local

  @test_path "tmp/local_provider_test"

  setup do
    File.rm_rf!(@test_path)
    File.mkdir_p!(@test_path)

    :ok = Local.init(%{base_path: @test_path})

    on_exit(fn ->
      File.rm_rf!(@test_path)
    end)

    :ok
  end

  describe "init/1" do
    test "creates base directory if it doesn't exist" do
      new_path = "tmp/new_local_storage"
      File.rm_rf!(new_path)

      :ok = Local.init(%{base_path: new_path})

      assert File.dir?(new_path)
      File.rm_rf!(new_path)
    end
  end

  describe "put_object/3" do
    test "stores binary data" do
      {:ok, metadata} = Local.put_object("test/file1", "content")

      assert metadata.key == "test/file1"
      assert metadata.size == 7
      assert metadata.content_type == "application/octet-stream"
      assert is_binary(metadata.etag)
    end

    test "accepts content_type option" do
      {:ok, metadata} = Local.put_object("test/file2", "content", content_type: "text/plain")

      assert metadata.content_type == "text/plain"
    end

    test "creates parent directories" do
      {:ok, _} = Local.put_object("deep/nested/path/file", "data")

      assert File.exists?(Path.join(@test_path, "deep/nested/path/file"))
    end
  end

  describe "get_object/1" do
    test "retrieves stored data" do
      content = "stored content"
      Local.put_object("get_test", content)

      {:ok, retrieved} = Local.get_object("get_test")

      assert retrieved == content
    end

    test "returns not_found for missing key" do
      {:error, :not_found} = Local.get_object("nonexistent")
    end
  end

  describe "delete_object/1" do
    test "removes file" do
      Local.put_object("delete_me", "data")
      assert Local.object_exists?("delete_me")

      :ok = Local.delete_object("delete_me")

      refute Local.object_exists?("delete_me")
    end

    test "is idempotent" do
      :ok = Local.delete_object("never_existed")
    end

    test "cleans up empty directories" do
      Local.put_object("clean/up/dirs/file", "data")
      :ok = Local.delete_object("clean/up/dirs/file")

      refute File.exists?(Path.join(@test_path, "clean/up/dirs"))
      refute File.exists?(Path.join(@test_path, "clean/up"))
      refute File.exists?(Path.join(@test_path, "clean"))
    end
  end

  describe "object_exists?/1" do
    test "returns true when object exists" do
      Local.put_object("exists", "data")

      assert Local.object_exists?("exists")
    end

    test "returns false when object doesn't exist" do
      refute Local.object_exists?("nope")
    end
  end

  describe "head_object/1" do
    test "returns metadata" do
      content = "head test content"
      Local.put_object("head_test", content)

      {:ok, metadata} = Local.head_object("head_test")

      assert metadata.key == "head_test"
      assert metadata.size == byte_size(content)
      assert %DateTime{} = metadata.last_modified
    end

    test "returns not_found for missing key" do
      {:error, :not_found} = Local.head_object("missing")
    end
  end

  describe "presigned_upload_url/2" do
    test "generates URL with token" do
      {:ok, url} = Local.presigned_upload_url("upload/key")

      assert String.contains?(url, "upload/key")
      assert String.contains?(url, "token=")
      assert String.contains?(url, "expires=")
    end

    test "accepts expires_in option" do
      {:ok, url1} = Local.presigned_upload_url("key1", expires_in: 60)
      {:ok, url2} = Local.presigned_upload_url("key2", expires_in: 3600)

      # Extract expiry from URLs
      [_, expires1] = Regex.run(~r/expires=(\d+)/, url1)
      [_, expires2] = Regex.run(~r/expires=(\d+)/, url2)

      assert String.to_integer(expires2) > String.to_integer(expires1)
    end
  end

  describe "presigned_download_url/2" do
    test "generates URL with token" do
      {:ok, url} = Local.presigned_download_url("download/key")

      assert String.contains?(url, "download/key")
      assert String.contains?(url, "token=")
      assert String.contains?(url, "expires=")
    end
  end

  describe "verify_token/4" do
    test "accepts valid token" do
      {:ok, url} = Local.presigned_upload_url("verify/key")

      # Parse URL to get token and expires
      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      expires = String.to_integer(query["expires"])
      token = query["token"]

      assert :ok = Local.verify_token("verify/key", :upload, token, expires)
    end

    test "rejects expired token" do
      past_expires = System.system_time(:second) - 100
      token = "any_token"

      {:error, :expired} = Local.verify_token("key", :upload, token, past_expires)
    end

    test "rejects invalid token" do
      future_expires = System.system_time(:second) + 100
      invalid_token = "invalid"

      {:error, :invalid_token} = Local.verify_token("key", :upload, invalid_token, future_expires)
    end
  end
end
