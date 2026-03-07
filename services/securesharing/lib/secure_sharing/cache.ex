defmodule SecureSharing.Cache do
  @moduledoc """
  In-memory ETS-based cache for frequently accessed data.

  Provides caching for:
  - Users (by ID)
  - Tenants (by ID and slug)
  - Public keys (by user ID)

  Cache entries have configurable TTL and are automatically expired.

  ## Memory Limits

  The cache enforces a maximum number of entries to prevent unbounded memory growth.
  When the limit is reached, the oldest entries (by insertion time) are evicted.
  Default limit is 10,000 entries.

  ## Configuration

  Configure via application environment:

      config :secure_sharing, SecureSharing.Cache,
        max_entries: 10_000,
        default_ttl_seconds: 300
  """
  use GenServer

  require Logger

  @table :secure_sharing_cache
  # 5 minutes
  @default_ttl_seconds 300
  # 1 minute
  @cleanup_interval_ms 60_000
  # Maximum cache entries
  @max_entries 10_000
  # Number of entries to evict when limit reached
  @eviction_batch_size 100

  # Client API

  @doc """
  Starts the cache GenServer and creates the ETS table.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a value from the cache.

  Returns `{:ok, value}` if found and not expired, `:miss` otherwise.
  """
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    now = System.system_time(:second)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at, _inserted_at}] when expires_at > now ->
        {:ok, value}

      _ ->
        :miss
    end
  end

  @doc """
  Puts a value in the cache with the default TTL.
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    put(key, value, @default_ttl_seconds)
  end

  @doc """
  Puts a value in the cache with a custom TTL in seconds.

  If the cache exceeds the maximum entry limit, old entries are evicted.
  """
  @spec put(term(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_seconds) do
    # Check if we need to evict entries
    maybe_evict_entries()

    expires_at = System.system_time(:second) + ttl_seconds
    inserted_at = System.system_time(:microsecond)
    :ets.insert(@table, {key, value, expires_at, inserted_at})
    :ok
  end

  @doc """
  Deletes a value from the cache.
  """
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc """
  Deletes all entries matching a pattern.
  Useful for invalidating related cache entries.

  Example: `delete_pattern({:user, _})` deletes all user cache entries.
  """
  @spec delete_pattern(term()) :: :ok
  def delete_pattern(pattern) do
    :ets.match_delete(@table, {pattern, :_, :_, :_})
    :ok
  end

  @doc """
  Clears all entries from the cache.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Returns cache statistics including memory usage and limits.
  """
  @spec stats() :: map()
  def stats do
    info = :ets.info(@table)
    size = info[:size]
    memory_bytes = info[:memory] * :erlang.system_info(:wordsize)
    max_entries = get_max_entries()

    %{
      size: size,
      max_entries: max_entries,
      utilization_percent: Float.round(size / max_entries * 100, 1),
      memory_bytes: memory_bytes,
      memory_mb: Float.round(memory_bytes / 1_048_576, 2)
    }
  end

  @doc """
  Returns the configured maximum entries limit.
  """
  @spec get_max_entries() :: pos_integer()
  def get_max_entries do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Keyword.get(:max_entries, @max_entries)
  end

  # User-specific cache functions

  @doc """
  Gets a user from cache by ID.
  """
  @spec get_user(String.t()) :: {:ok, term()} | :miss
  def get_user(user_id) do
    get({:user, user_id})
  end

  @doc """
  Caches a user by ID.
  """
  @spec put_user(String.t(), term()) :: :ok
  def put_user(user_id, user) do
    put({:user, user_id}, user)
  end

  @doc """
  Invalidates a user's cache entry.
  """
  @spec invalidate_user(String.t()) :: :ok
  def invalidate_user(user_id) do
    delete({:user, user_id})
    # Also invalidate any related caches
    delete({:user_public_keys, user_id})
  end

  # Tenant-specific cache functions

  @doc """
  Gets a tenant from cache by ID.
  """
  @spec get_tenant(String.t()) :: {:ok, term()} | :miss
  def get_tenant(tenant_id) do
    get({:tenant, tenant_id})
  end

  @doc """
  Gets a tenant from cache by slug.
  """
  @spec get_tenant_by_slug(String.t()) :: {:ok, term()} | :miss
  def get_tenant_by_slug(slug) do
    get({:tenant_slug, slug})
  end

  @doc """
  Caches a tenant by ID and slug.
  """
  @spec put_tenant(term()) :: :ok
  def put_tenant(tenant) do
    put({:tenant, tenant.id}, tenant)
    put({:tenant_slug, tenant.slug}, tenant)
  end

  @doc """
  Invalidates a tenant's cache entries.
  """
  @spec invalidate_tenant(String.t(), String.t()) :: :ok
  def invalidate_tenant(tenant_id, slug) do
    delete({:tenant, tenant_id})
    delete({:tenant_slug, slug})
  end

  # Public key cache functions

  @doc """
  Gets public keys from cache by user ID.
  """
  @spec get_public_keys(String.t()) :: {:ok, term()} | :miss
  def get_public_keys(user_id) do
    get({:user_public_keys, user_id})
  end

  @doc """
  Caches public keys by user ID with a longer TTL (30 minutes).
  Public keys change infrequently.
  """
  @spec put_public_keys(String.t(), term()) :: :ok
  def put_public_keys(user_id, public_keys) do
    # 30 minutes
    put({:user_public_keys, user_id}, public_keys, 1800)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired do
    now = System.system_time(:second)
    # Delete all entries where expires_at <= now
    # Match spec for {key, value, expires_at, inserted_at} tuples
    match_spec = [{{:_, :_, :"$1", :_}, [{:"=<", :"$1", now}], [true]}]
    deleted = :ets.select_delete(@table, match_spec)

    if deleted > 0 do
      Logger.debug("Cache cleanup: removed #{deleted} expired entries")
    end
  end

  # Evict oldest entries if cache size exceeds limit
  defp maybe_evict_entries do
    max_entries = get_max_entries()
    current_size = :ets.info(@table, :size)

    if current_size >= max_entries do
      evict_oldest_entries(@eviction_batch_size)
    end
  end

  # Evict the N oldest entries based on insertion time
  defp evict_oldest_entries(count) do
    # Get all entries with their insertion times
    entries = :ets.tab2list(@table)

    # Sort by insertion time (4th element) ascending (oldest first)
    sorted = Enum.sort_by(entries, fn {_key, _value, _expires, inserted_at} -> inserted_at end)

    # Take the oldest N entries and delete them
    to_delete = Enum.take(sorted, count)

    Enum.each(to_delete, fn {key, _, _, _} ->
      :ets.delete(@table, key)
    end)

    Logger.info(
      "Cache eviction: removed #{length(to_delete)} oldest entries (limit: #{get_max_entries()})"
    )
  end
end
