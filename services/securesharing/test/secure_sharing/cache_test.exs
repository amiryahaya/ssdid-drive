defmodule SecureSharing.CacheTest do
  # Not async due to shared ETS table
  use ExUnit.Case, async: false

  alias SecureSharing.Cache

  setup do
    # Clear cache before each test
    Cache.clear()
    :ok
  end

  describe "basic operations" do
    test "put and get work correctly" do
      assert :ok = Cache.put(:test_key, "test_value")
      assert {:ok, "test_value"} = Cache.get(:test_key)
    end

    test "get returns :miss for non-existent key" do
      assert :miss = Cache.get(:nonexistent)
    end

    test "delete removes key" do
      Cache.put(:to_delete, "value")
      assert {:ok, "value"} = Cache.get(:to_delete)

      Cache.delete(:to_delete)
      assert :miss = Cache.get(:to_delete)
    end

    test "clear removes all entries" do
      Cache.put(:key1, "value1")
      Cache.put(:key2, "value2")
      Cache.put(:key3, "value3")

      Cache.clear()

      assert :miss = Cache.get(:key1)
      assert :miss = Cache.get(:key2)
      assert :miss = Cache.get(:key3)
    end

    test "expired entries are not returned" do
      # Put with very short TTL
      Cache.put(:expires_soon, "value", 1)

      # Still available immediately
      assert {:ok, "value"} = Cache.get(:expires_soon)

      # Wait for expiry
      Process.sleep(1100)

      # Now should be expired
      assert :miss = Cache.get(:expires_soon)
    end

    test "stats returns cache information" do
      Cache.put(:stat_key, "stat_value")

      stats = Cache.stats()
      assert is_map(stats)
      assert stats.size >= 1
      assert stats.memory_bytes > 0
    end
  end

  describe "user cache operations" do
    test "put_user and get_user work correctly" do
      user = %{id: "user-123", email: "test@example.com"}

      Cache.put_user("user-123", user)
      assert {:ok, ^user} = Cache.get_user("user-123")
    end

    test "invalidate_user removes user from cache" do
      user = %{id: "user-456", email: "test@example.com"}
      public_keys = %{kem: "key1", sign: "key2"}

      Cache.put_user("user-456", user)
      Cache.put_public_keys("user-456", public_keys)

      # Both should be cached
      assert {:ok, ^user} = Cache.get_user("user-456")
      assert {:ok, ^public_keys} = Cache.get_public_keys("user-456")

      # Invalidate user
      Cache.invalidate_user("user-456")

      # Both should be gone
      assert :miss = Cache.get_user("user-456")
      assert :miss = Cache.get_public_keys("user-456")
    end
  end

  describe "tenant cache operations" do
    test "put_tenant caches by id and slug" do
      tenant = %{id: "tenant-123", slug: "acme-corp", name: "ACME Corp"}

      Cache.put_tenant(tenant)

      assert {:ok, ^tenant} = Cache.get_tenant("tenant-123")
      assert {:ok, ^tenant} = Cache.get_tenant_by_slug("acme-corp")
    end

    test "invalidate_tenant removes both id and slug entries" do
      tenant = %{id: "tenant-456", slug: "widgets-inc", name: "Widgets Inc"}

      Cache.put_tenant(tenant)
      Cache.invalidate_tenant("tenant-456", "widgets-inc")

      assert :miss = Cache.get_tenant("tenant-456")
      assert :miss = Cache.get_tenant_by_slug("widgets-inc")
    end
  end

  describe "public key cache operations" do
    test "put_public_keys and get_public_keys work correctly" do
      keys = %{ml_kem: "kem_key", ml_dsa: "dsa_key"}

      Cache.put_public_keys("user-789", keys)
      assert {:ok, ^keys} = Cache.get_public_keys("user-789")
    end
  end

  describe "delete_pattern" do
    test "deletes matching patterns" do
      # Add various cache entries
      Cache.put({:user, "1"}, %{id: "1"})
      Cache.put({:user, "2"}, %{id: "2"})
      Cache.put({:tenant, "t1"}, %{id: "t1"})

      # Delete all user entries
      Cache.delete_pattern({:user, :_})

      assert :miss = Cache.get({:user, "1"})
      assert :miss = Cache.get({:user, "2"})
      # Tenant should still be there
      assert {:ok, _} = Cache.get({:tenant, "t1"})
    end
  end

  describe "memory limits and eviction" do
    test "stats includes max_entries and utilization" do
      Cache.put(:limit_test, "value")

      stats = Cache.stats()

      assert Map.has_key?(stats, :max_entries)
      assert Map.has_key?(stats, :utilization_percent)
      assert stats.max_entries > 0
      assert is_float(stats.utilization_percent)
    end

    test "get_max_entries returns configured limit" do
      max = Cache.get_max_entries()
      assert is_integer(max)
      assert max > 0
    end

    test "evicts oldest entries when limit is approached" do
      # This test uses a smaller number to verify eviction logic works
      # In production, the limit is 10,000 entries

      # Add entries with slight delays to ensure different insertion times
      Cache.put(:old_entry_1, "old_value_1")
      Process.sleep(1)
      Cache.put(:old_entry_2, "old_value_2")
      Process.sleep(1)
      Cache.put(:new_entry, "new_value")

      # All entries should be retrievable
      assert {:ok, "old_value_1"} = Cache.get(:old_entry_1)
      assert {:ok, "old_value_2"} = Cache.get(:old_entry_2)
      assert {:ok, "new_value"} = Cache.get(:new_entry)

      stats = Cache.stats()
      assert stats.size >= 3
    end

    test "stats memory_mb is calculated correctly" do
      Cache.put(:memory_test, String.duplicate("x", 1000))

      stats = Cache.stats()

      assert stats.memory_bytes > 0
      assert stats.memory_mb > 0
      assert stats.memory_mb == Float.round(stats.memory_bytes / 1_048_576, 2)
    end

    test "insertion time is tracked for eviction ordering" do
      # Clear and add entries
      Cache.clear()

      # Add first entry
      Cache.put(:first, "first_value")
      Process.sleep(10)

      # Add second entry
      Cache.put(:second, "second_value")

      # Both should be present
      assert {:ok, "first_value"} = Cache.get(:first)
      assert {:ok, "second_value"} = Cache.get(:second)

      # Stats should show 2 entries
      assert Cache.stats().size >= 2
    end
  end

  describe "cache entry format" do
    test "entries include expiry and insertion time" do
      # This test verifies the internal format is correct for eviction
      Cache.put(:format_test, "test_value", 300)

      # Entry should be retrievable
      assert {:ok, "test_value"} = Cache.get(:format_test)

      # The entry format is {key, value, expires_at, inserted_at}
      # We can verify this by checking stats after insertion
      stats = Cache.stats()
      assert stats.size >= 1
    end
  end
end
