defmodule SecureSharing.Files do
  @moduledoc """
  The Files context for managing folders and files with zero-knowledge encryption.

  This context handles:
  - Folder hierarchy with KEK (Key Encryption Key) wrapping
  - File management with DEK (Data Encryption Key) wrapping
  - Cryptographic operations are performed client-side; server only stores encrypted data

  Key Hierarchy:
  - User's PQC keypair wraps root folder's KEK
  - Parent folder's KEK wraps child folder's KEK
  - Folder's KEK wraps file's DEK
  """

  import Ecto.Query, warn: false
  alias SecureSharing.Repo
  alias SecureSharing.Files.{Folder, File}
  alias SecureSharing.Accounts.User

  # ============================================================================
  # Folders
  # ============================================================================

  @doc """
  Creates a root folder for a user.

  A root folder is the top-level folder for a user's vault.
  Each user can have only one root folder.
  The KEK is wrapped directly with the user's PQC public key.

  ## Parameters
  - user: The user to create the root folder for
  - attrs: Map containing:
    - wrapped_kek: KEK wrapped with user's public key
    - kem_ciphertext: KEM ciphertext for unwrapping
    - owner_wrapped_kek: Same as wrapped_kek for root
    - owner_kem_ciphertext: Same as kem_ciphertext for root
    - encrypted_metadata: Optional encrypted folder name
  """
  def create_root_folder(%User{} = user, attrs) do
    attrs =
      attrs
      |> Map.put(:tenant_id, user.tenant_id)
      |> Map.put(:owner_id, user.id)
      |> Map.put(:is_root, true)
      |> Map.put(:parent_id, nil)

    %Folder{}
    |> Folder.root_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a child folder under a parent folder.

  The new folder's KEK is wrapped with the parent folder's KEK.
  Owner access is provided via owner_wrapped_kek (wrapped with user's public key).

  ## Authorization
  - User must be in the same tenant as the parent folder
  - User must have write permission on the parent folder (owner or write/admin share)

  ## Parameters
  - parent: The parent folder
  - user: The user creating the folder (must have write access to parent)
  - attrs: Map containing:
    - wrapped_kek: KEK wrapped with parent's KEK
    - kem_ciphertext: KEM ciphertext for unwrapping
    - owner_wrapped_kek: KEK wrapped with user's public key
    - owner_kem_ciphertext: KEM ciphertext for owner access
    - encrypted_metadata: Encrypted folder name
  """
  def create_folder(%Folder{} = parent, %User{} = user, attrs) do
    cond do
      # Prevent cross-tenant operations
      user.tenant_id != parent.tenant_id ->
        {:error, :cross_tenant_operation}

      # Verify user can write to parent folder (owner or write/admin share)
      not can_write_folder?(user, parent) ->
        {:error, :forbidden}

      true ->
        attrs =
          attrs
          |> Map.put(:tenant_id, parent.tenant_id)
          |> Map.put(:owner_id, user.id)
          |> Map.put(:parent_id, parent.id)
          |> Map.put(:is_root, false)

        %Folder{}
        |> Folder.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Gets a folder by ID.
  """
  def get_folder(id), do: Repo.get(Folder, id)

  @doc """
  Gets a folder by ID with preloads.
  """
  def get_folder(id, preloads) when is_list(preloads) do
    Folder
    |> Repo.get(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Gets a folder by ID with preloaded associations.
  """
  def get_folder!(id, preloads \\ []) do
    Folder
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Gets the root folder for a user.
  """
  def get_root_folder(%User{id: user_id}) do
    Folder
    |> where([f], f.owner_id == ^user_id and f.is_root == true)
    |> Repo.one()
  end

  @doc """
  Gets the root folder for a user, creating one if it doesn't exist.
  """
  def get_or_create_root_folder(%User{} = user, attrs) do
    case get_root_folder(user) do
      nil -> create_root_folder(user, attrs)
      folder -> {:ok, folder}
    end
  end

  @doc """
  Lists all folders owned by a user.
  """
  def list_user_folders(user, opts \\ %{})

  def list_user_folders(%User{id: user_id}, opts) when is_map(opts) do
    query =
      Folder
      |> where([f], f.owner_id == ^user_id)
      |> order_by([f], asc: f.is_root, asc: f.created_at)

    query = maybe_paginate(query, opts)
    Repo.all(query)
  end

  @doc """
  Counts folders owned by a user.
  """
  def count_user_folders(%User{id: user_id}) do
    Folder
    |> where([f], f.owner_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists child folders of a parent folder with optional pagination.
  """
  def list_child_folders(folder, opts \\ %{})

  def list_child_folders(%Folder{id: folder_id}, opts) when is_map(opts) do
    query =
      Folder
      |> where([f], f.parent_id == ^folder_id)
      |> order_by([f], asc: f.created_at)

    query = maybe_paginate(query, opts)
    Repo.all(query)
  end

  @doc """
  Counts child folders of a parent folder.
  """
  def count_child_folders(%Folder{id: folder_id}) do
    Folder
    |> where([f], f.parent_id == ^folder_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Updates folder metadata.
  Only encrypted_metadata can be updated.
  """
  def update_folder_metadata(%Folder{} = folder, attrs) do
    folder
    |> Folder.metadata_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a folder to a new parent.

  Requires re-wrapping the KEK with the new parent's KEK and re-signing.
  """
  def move_folder(%Folder{} = folder, %Folder{} = new_parent, %User{} = user, attrs) do
    cond do
      folder.tenant_id != new_parent.tenant_id ->
        {:error, :cross_tenant_operation}

      user.tenant_id != folder.tenant_id ->
        {:error, :cross_tenant_operation}

      not can_write_folder?(user, folder) ->
        {:error, :forbidden}

      not can_write_folder?(user, new_parent) ->
        {:error, :forbidden}

      folder.id == new_parent.id ->
        {:error, :conflict}

      folder.id in get_ancestor_folder_ids(new_parent.id) ->
        {:error, :conflict}

      true ->
        attrs = Map.put(attrs, :parent_id, new_parent.id)

        folder
        |> Folder.move_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a folder and all its contents (children and files).
  Uses database cascading for cleanup.
  """
  def delete_folder(%Folder{is_root: true}), do: {:error, :cannot_delete_root}

  def delete_folder(%Folder{} = folder) do
    Repo.delete(folder)
  end

  @doc """
  Gets the folder hierarchy path from root to the given folder.

  NOTE: This uses recursive queries. For access checks, prefer `get_ancestor_folder_ids/1`
  which fetches all ancestors in a single query.
  """
  def get_folder_path(%Folder{} = folder) do
    get_folder_path_recursive(folder, [])
  end

  defp get_folder_path_recursive(%Folder{parent_id: nil} = folder, acc) do
    [folder | acc]
  end

  defp get_folder_path_recursive(%Folder{parent_id: parent_id} = folder, acc) do
    parent = get_folder!(parent_id)
    get_folder_path_recursive(parent, [folder | acc])
  end

  @doc """
  Gets all ancestor folder IDs for a folder using a single recursive CTE query.

  Returns a list of folder IDs from the immediate parent up to the root,
  including the input folder itself.

  This is optimized for access control checks to avoid N+1 queries.

  ## Examples

      iex> get_ancestor_folder_ids("child-folder-id")
      ["child-folder-id", "parent-folder-id", "grandparent-folder-id", "root-folder-id"]
  """
  @spec get_ancestor_folder_ids(String.t()) :: [String.t()]
  def get_ancestor_folder_ids(folder_id) when is_binary(folder_id) do
    # Use a recursive CTE to get all ancestor folders in one query
    # This avoids N+1 queries when checking folder hierarchy access
    query = """
    WITH RECURSIVE folder_ancestors AS (
      -- Base case: start with the given folder
      SELECT id, parent_id, owner_id, 0 as depth
      FROM folders
      WHERE id = $1

      UNION ALL

      -- Recursive case: get parent folders
      SELECT f.id, f.parent_id, f.owner_id, fa.depth + 1
      FROM folders f
      INNER JOIN folder_ancestors fa ON f.id = fa.parent_id
    )
    SELECT id, owner_id FROM folder_ancestors ORDER BY depth ASC
    """

    case Repo.query(query, [Ecto.UUID.dump!(folder_id)]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, _owner_id] ->
          {:ok, uuid} = Ecto.UUID.load(id)
          uuid
        end)

      {:error, _} ->
        []
    end
  end

  def get_ancestor_folder_ids(nil), do: []

  @doc """
  Gets all ancestor folders with their owners for access checking.

  Returns a list of {folder_id, owner_id} tuples from the folder up to root.

  This is optimized for permission checks in sharing.
  """
  @spec get_ancestor_folders_with_owners(String.t()) :: [{String.t(), String.t()}]
  def get_ancestor_folders_with_owners(folder_id) when is_binary(folder_id) do
    query = """
    WITH RECURSIVE folder_ancestors AS (
      SELECT id, parent_id, owner_id, 0 as depth
      FROM folders
      WHERE id = $1

      UNION ALL

      SELECT f.id, f.parent_id, f.owner_id, fa.depth + 1
      FROM folders f
      INNER JOIN folder_ancestors fa ON f.id = fa.parent_id
    )
    SELECT id, owner_id FROM folder_ancestors ORDER BY depth ASC
    """

    case Repo.query(query, [Ecto.UUID.dump!(folder_id)]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, owner_id] ->
          {:ok, folder_uuid} = Ecto.UUID.load(id)
          {:ok, owner_uuid} = Ecto.UUID.load(owner_id)
          {folder_uuid, owner_uuid}
        end)

      {:error, _} ->
        []
    end
  end

  def get_ancestor_folders_with_owners(nil), do: []

  # ============================================================================
  # Files
  # ============================================================================

  @doc """
  Creates a file in a folder.

  The file's DEK is wrapped with the folder's KEK.
  The signature covers the hash of: encrypted blob + wrapped DEK + encrypted metadata.

  ## Authorization
  - User must be in the same tenant as the folder
  - User must have write permission on the folder (owner or write/admin share)

  ## Parameters
  - folder: The parent folder
  - user: The user creating the file (must have write access to folder)
  - attrs: Map containing:
    - encrypted_metadata: Encrypted filename/metadata
    - wrapped_dek: DEK wrapped with folder's KEK
    - kem_ciphertext: KEM ciphertext for unwrapping
    - signature: Owner's signature
    - storage_path: Path to encrypted blob
    - blob_size: Size of encrypted blob
    - blob_hash: Hash of ciphertext
  """
  # Create file in root folder (folder_id = nil)
  def create_file(nil, %User{} = user, attrs) do
    # Use tenant_id from attrs if provided (from JWT), otherwise fall back to user.tenant_id
    tenant_id = Map.get(attrs, :tenant_id) || user.tenant_id

    attrs =
      attrs
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:owner_id, user.id)
      |> Map.put(:folder_id, nil)

    %File{}
    |> File.changeset(attrs)
    |> Repo.insert()
  end

  def create_file(%Folder{} = folder, %User{} = user, attrs) do
    cond do
      # Prevent cross-tenant operations
      user.tenant_id != folder.tenant_id ->
        {:error, :cross_tenant_operation}

      # Verify user can write to folder (owner or write/admin share)
      not can_write_folder?(user, folder) ->
        {:error, :forbidden}

      true ->
        attrs =
          attrs
          |> Map.put(:tenant_id, folder.tenant_id)
          |> Map.put(:owner_id, user.id)
          |> Map.put(:folder_id, folder.id)

        %File{}
        |> File.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Gets a file by ID.
  """
  def get_file(id), do: Repo.get(File, id)

  @doc """
  Gets a file by ID, raises if not found.
  """
  def get_file!(id, preloads \\ []) do
    File
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Gets a file by storage path.
  """
  def get_file_by_storage_path(storage_path) do
    File
    |> where([f], f.storage_path == ^storage_path)
    |> Repo.one()
  end

  @doc """
  Lists all files in a folder with optional pagination.

  ## Options

  - `:offset` - Number of records to skip (default: 0)
  - `:limit` - Maximum number of records to return (default: all)

  ## Examples

      list_folder_files(folder)
      list_folder_files(folder, %{offset: 0, limit: 20})
  """
  def list_folder_files(folder, opts \\ %{})

  def list_folder_files(%Folder{id: folder_id}, opts) when is_map(opts) do
    query =
      File
      |> where([f], f.folder_id == ^folder_id)
      |> order_by([f], asc: f.created_at)

    query = maybe_paginate(query, opts)
    Repo.all(query)
  end

  @doc """
  Counts files in a folder.
  """
  def count_folder_files(%Folder{id: folder_id}) do
    File
    |> where([f], f.folder_id == ^folder_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists all files owned by a user.
  """
  def list_user_files(%User{id: user_id}) do
    File
    |> where([f], f.owner_id == ^user_id)
    |> order_by([f], desc: f.created_at)
    |> Repo.all()
  end

  @doc """
  Lists all files accessible to a user (owned + shared via active share grants).

  Returns `{files, total_count}` for pagination.

  Used by clients for local search — the server cannot search encrypted metadata
  (zero-knowledge), so it returns all accessible files for client-side filtering.

  ## Options
  - `:status` — filter by file status (e.g., "complete")
  """
  def list_accessible_files(%User{id: user_id} = _user, pagination, opts \\ []) do
    now = DateTime.utc_now()
    status = Keyword.get(opts, :status)

    # Subquery: file IDs shared with user via active, non-expired share grants
    shared_file_ids =
      from(sg in SecureSharing.Sharing.ShareGrant,
        where: sg.grantee_id == ^user_id,
        where: sg.resource_type == :file,
        where: is_nil(sg.revoked_at),
        where: is_nil(sg.expires_at) or sg.expires_at > ^now,
        select: sg.resource_id
      )

    # Subquery: folder IDs shared with user (for files inside shared folders)
    shared_folder_ids =
      from(sg in SecureSharing.Sharing.ShareGrant,
        where: sg.grantee_id == ^user_id,
        where: sg.resource_type == :folder,
        where: is_nil(sg.revoked_at),
        where: is_nil(sg.expires_at) or sg.expires_at > ^now,
        select: sg.resource_id
      )

    # Union: files owned by user OR directly shared OR in a shared folder
    query =
      File
      |> where(
        [f],
        f.owner_id == ^user_id or f.id in subquery(shared_file_ids) or
          f.folder_id in subquery(shared_folder_ids)
      )
      |> order_by([f], desc: f.created_at)

    # Optional status filter
    query = if status, do: where(query, [f], f.status == ^status), else: query

    total_count = Repo.aggregate(query, :count)
    files = query |> maybe_paginate(pagination) |> Repo.all()

    {files, total_count}
  end

  @doc """
  Updates file status during upload.
  """
  def update_file_status(%File{} = file, attrs) do
    file
    |> File.status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a file to a different folder.

  Requires re-wrapping the DEK with the new folder's KEK and re-signing.

  Validates:
  - File and destination folder are in the same tenant
  - User has write permission on the file (owner or write/admin share)
  - User has write permission on the destination folder
  """
  def move_file(%File{} = file, %Folder{} = new_folder, %User{} = user, attrs) do
    cond do
      # Prevent cross-tenant moves
      file.tenant_id != new_folder.tenant_id ->
        {:error, :cross_tenant_operation}

      # User must be in the same tenant
      user.tenant_id != file.tenant_id ->
        {:error, :cross_tenant_operation}

      # Verify user can write to the file (owner or write/admin permission)
      not can_write_file?(user, file) ->
        {:error, :forbidden}

      # Verify user can write to destination folder
      not can_write_folder?(user, new_folder) ->
        {:error, :forbidden}

      true ->
        attrs = Map.put(attrs, :folder_id, new_folder.id)

        file
        |> File.move_changeset(attrs)
        |> Repo.update()
    end
  end

  # Check if user can write to a file
  defp can_write_file?(%User{id: user_id}, %File{owner_id: owner_id}) when user_id == owner_id,
    do: true

  defp can_write_file?(%User{} = user, %File{} = file) do
    SecureSharing.Sharing.can_write_file?(user, file)
  end

  # Check if user can write to a folder
  defp can_write_folder?(%User{id: user_id}, %Folder{owner_id: owner_id})
       when user_id == owner_id,
       do: true

  defp can_write_folder?(%User{} = user, %Folder{} = folder) do
    SecureSharing.Sharing.can_write_folder?(user, folder)
  end

  @doc """
  Deletes a file.
  Note: The encrypted blob should be deleted separately from storage.
  """
  def delete_file(%File{} = file) do
    Repo.delete(file)
  end

  @doc """
  Calculates total storage used by a user (sum of blob_size).
  Returns an integer.
  """
  def calculate_user_storage(%User{id: user_id}) do
    result =
      File
      |> where([f], f.owner_id == ^user_id)
      |> select([f], sum(f.blob_size))
      |> Repo.one()

    decimal_to_integer(result)
  end

  @doc """
  Calculates total storage used by a tenant.
  Returns an integer.
  """
  def calculate_tenant_storage(tenant_id) do
    result =
      File
      |> where([f], f.tenant_id == ^tenant_id)
      |> select([f], sum(f.blob_size))
      |> Repo.one()

    decimal_to_integer(result)
  end

  defp decimal_to_integer(nil), do: 0
  defp decimal_to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp decimal_to_integer(n) when is_integer(n), do: n

  @doc """
  Checks if user has remaining storage quota.
  """
  def has_storage_quota?(%User{} = user, additional_bytes) do
    has_storage_quota_by_tenant?(user.tenant_id, additional_bytes)
  end

  @doc """
  Checks if tenant has remaining storage quota by tenant_id.
  """
  def has_storage_quota_by_tenant?(tenant_id, additional_bytes) when is_binary(tenant_id) do
    tenant = SecureSharing.Accounts.get_tenant(tenant_id)
    current_usage = calculate_tenant_storage(tenant_id)
    current_usage + additional_bytes <= tenant.storage_quota_bytes
  end

  def has_storage_quota_by_tenant?(nil, _additional_bytes), do: false

  ## Admin Functions

  @doc """
  Counts total number of files.
  """
  def count_files do
    Repo.aggregate(File, :count, :id)
  end

  @doc """
  Counts total number of folders.
  """
  def count_folders do
    Repo.aggregate(Folder, :count, :id)
  end

  @doc """
  Counts files in a specific tenant.
  """
  def count_tenant_files(tenant_id) do
    File
    |> where([f], f.tenant_id == ^tenant_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Calculates total storage across all tenants.
  Returns an integer (bytes).
  """
  def calculate_total_storage do
    result =
      File
      |> select([f], sum(f.blob_size))
      |> Repo.one()

    decimal_to_integer(result)
  end

  @doc """
  Gets file statistics for a specific tenant.
  Returns %{file_count: integer, storage_bytes: integer}.
  """
  def get_tenant_file_stats(tenant_id) do
    result =
      File
      |> where([f], f.tenant_id == ^tenant_id)
      |> select([f], %{file_count: count(f.id), storage_bytes: sum(f.blob_size)})
      |> Repo.one()

    %{
      file_count: result.file_count || 0,
      storage_bytes: decimal_to_integer(result.storage_bytes)
    }
  end

  @doc """
  Gets file statistics for all tenants (for super admin dashboard).
  Returns a list of maps with tenant info and file stats.

  ## Options
  - `:order_by` - Field to order by (:name, :storage, :files). Default: :storage (desc)
  - `:limit` - Maximum number of tenants to return. Default: all
  """
  def get_all_tenants_file_stats(opts \\ []) do
    order_by = Keyword.get(opts, :order_by, :storage)
    limit = Keyword.get(opts, :limit)

    # Query files grouped by tenant with stats
    file_stats_query =
      File
      |> group_by([f], f.tenant_id)
      |> select([f], %{
        tenant_id: f.tenant_id,
        file_count: count(f.id),
        storage_bytes: sum(f.blob_size)
      })

    file_stats = Repo.all(file_stats_query)
    file_stats_map = Map.new(file_stats, fn s -> {s.tenant_id, s} end)

    # Get all tenants
    tenants = SecureSharing.Accounts.list_tenants()

    # Combine tenant info with file stats
    results =
      Enum.map(tenants, fn tenant ->
        stats = Map.get(file_stats_map, tenant.id, %{file_count: 0, storage_bytes: nil})

        %{
          tenant_id: tenant.id,
          tenant_name: tenant.name,
          tenant_slug: tenant.slug,
          storage_quota_bytes: tenant.storage_quota_bytes,
          file_count: stats.file_count || 0,
          storage_bytes: decimal_to_integer(stats.storage_bytes),
          storage_percentage:
            if tenant.storage_quota_bytes > 0 do
              Float.round(
                decimal_to_integer(stats.storage_bytes) / tenant.storage_quota_bytes * 100,
                1
              )
            else
              0.0
            end
        }
      end)

    # Sort results
    sorted =
      case order_by do
        :name -> Enum.sort_by(results, & &1.tenant_name)
        :files -> Enum.sort_by(results, & &1.file_count, :desc)
        :storage -> Enum.sort_by(results, & &1.storage_bytes, :desc)
        _ -> Enum.sort_by(results, & &1.storage_bytes, :desc)
      end

    # Apply limit if specified
    if limit, do: Enum.take(sorted, limit), else: sorted
  end

  # Private Helpers

  defp maybe_paginate(query, %{offset: offset, limit: limit}) do
    query
    |> offset(^offset)
    |> limit(^limit)
  end

  defp maybe_paginate(query, _opts), do: query
end
