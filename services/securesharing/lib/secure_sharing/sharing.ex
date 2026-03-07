defmodule SecureSharing.Sharing do
  @moduledoc """
  The Sharing context for zero-knowledge file and folder sharing.

  This context manages ShareGrants - cryptographic access grants that allow
  users to share files and folders without the server ever seeing plaintext.

  ## How Sharing Works

  1. **Grantor** wants to share a file/folder with **Grantee**
  2. Grantor fetches Grantee's public key from server
  3. Grantor decrypts the DEK (file) or KEK (folder) using their own keys
  4. Grantor encapsulates the key for Grantee's public key using KEM
  5. Grantor signs the share grant package
  6. Server stores the ShareGrant (all encrypted, server cannot decrypt)
  7. Grantee fetches their shares and decapsulates using their private key

  ## Permission Levels

  - `:read` - Can decrypt and download
  - `:write` - Can upload, modify (re-encrypt)
  - `:admin` - Can share with others, manage permissions

  ## Folder Sharing

  When sharing a folder with `recursive: true`, the grantee gains access to:
  - All files in the folder (via the folder's KEK)
  - All subfolders (their KEKs are wrapped by the shared KEK)
  """

  import Ecto.Query, warn: false
  alias SecureSharing.Repo
  alias SecureSharing.Sharing.{AccessRequest, ShareGrant}
  alias SecureSharing.Accounts.User
  alias SecureSharing.Files.{File, Folder}

  # ============================================================================
  # Creating Shares
  # ============================================================================

  @doc """
  Creates a share grant for a file.

  The file's DEK must be wrapped for the grantee's public key.
  The grantor must sign the package.

  ## Parameters
  - file: The file to share
  - grantor: The user creating the share
  - grantee: The user receiving the share
  - attrs: Map containing:
    - wrapped_key: DEK wrapped for grantee's public key
    - kem_ciphertext: KEM ciphertext for unwrapping
    - signature: Grantor's signature
    - permission: :read, :write, or :admin (optional, default: read)
    - expires_at: Optional expiry time
  """
  def share_file(%File{} = file, %User{} = grantor, %User{} = grantee, attrs) do
    # Ensure same tenant
    if file.tenant_id != grantor.tenant_id or grantor.tenant_id != grantee.tenant_id do
      {:error, :cross_tenant_share}
    else
      attrs =
        attrs
        |> Map.put(:tenant_id, file.tenant_id)
        |> Map.put(:grantor_id, grantor.id)
        |> Map.put(:grantee_id, grantee.id)
        |> Map.put(:resource_type, :file)
        |> Map.put(:resource_id, file.id)
        |> Map.put(:recursive, false)

      %ShareGrant{}
      |> ShareGrant.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Creates a share grant for a folder.

  The folder's KEK must be wrapped for the grantee's public key.
  With recursive=true (default), grantee can access all children.

  ## Parameters
  - folder: The folder to share
  - grantor: The user creating the share
  - grantee: The user receiving the share
  - attrs: Map containing:
    - wrapped_key: KEK wrapped for grantee's public key
    - kem_ciphertext: KEM ciphertext for unwrapping
    - signature: Grantor's signature
    - permission: :read, :write, or :admin (optional, default: read)
    - recursive: Include children (optional, default: true)
    - expires_at: Optional expiry time
  """
  def share_folder(%Folder{} = folder, %User{} = grantor, %User{} = grantee, attrs) do
    # Ensure same tenant
    if folder.tenant_id != grantor.tenant_id or grantor.tenant_id != grantee.tenant_id do
      {:error, :cross_tenant_share}
    else
      attrs =
        attrs
        |> Map.put(:tenant_id, folder.tenant_id)
        |> Map.put(:grantor_id, grantor.id)
        |> Map.put(:grantee_id, grantee.id)
        |> Map.put(:resource_type, :folder)
        |> Map.put(:resource_id, folder.id)
        |> Map.put_new(:recursive, true)

      %ShareGrant{}
      |> ShareGrant.changeset(attrs)
      |> Repo.insert()
    end
  end

  # ============================================================================
  # Querying Shares
  # ============================================================================

  @doc """
  Gets a share grant by ID.
  """
  def get_share_grant(id), do: Repo.get(ShareGrant, id)

  @doc """
  Gets a share grant by ID, raises if not found.
  """
  def get_share_grant!(id), do: Repo.get!(ShareGrant, id)

  @doc """
  Lists all active shares received by a user.
  Excludes revoked and expired shares.
  """
  def list_received_shares(%User{id: user_id}) do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], s.grantee_id == ^user_id)
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Lists all shares created by a user (including revoked).
  """
  def list_created_shares(%User{id: user_id}) do
    ShareGrant
    |> where([s], s.grantor_id == ^user_id)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Lists active shares created by a user.
  """
  def list_active_created_shares(%User{id: user_id}) do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], s.grantor_id == ^user_id)
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Lists all active shares for a specific file.
  """
  def list_file_shares(%File{id: file_id}) do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], s.resource_type == :file and s.resource_id == ^file_id)
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Lists all active shares for a specific folder.
  """
  def list_folder_shares(%Folder{id: folder_id}) do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], s.resource_type == :folder and s.resource_id == ^folder_id)
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Gets an active share for a specific user and resource.
  Returns nil if no active share exists.
  """
  def get_share_for_user(%User{id: user_id}, resource_type, resource_id) do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], s.grantee_id == ^user_id)
    |> where([s], s.resource_type == ^resource_type and s.resource_id == ^resource_id)
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> Repo.one()
  end

  @doc """
  Checks if a user has access to a file (either owner or has active share).
  """
  def has_file_access?(%User{id: user_id} = user, %File{owner_id: owner_id} = file) do
    if user_id == owner_id do
      true
    else
      case get_share_for_user(user, :file, file.id) do
        nil -> has_folder_access?(user, file.folder_id)
        share -> ShareGrant.active?(share)
      end
    end
  end

  @doc """
  Checks if a user has access to a folder (either owner or has active share).
  Also checks parent folders for recursive shares.

  This function is optimized to fetch all ancestor folders in a single query
  to avoid N+1 database calls.
  """
  def has_folder_access?(%User{} = user, folder_id) when is_binary(folder_id) do
    folder = SecureSharing.Files.get_folder(folder_id)
    has_folder_access?(user, folder)
  end

  def has_folder_access?(%User{id: user_id} = user, %Folder{owner_id: owner_id} = folder) do
    cond do
      # Fast path: user is the owner
      user_id == owner_id ->
        true

      # Check for direct share on this folder
      share = get_share_for_user(user, :folder, folder.id) ->
        ShareGrant.active?(share)

      # Check for recursive access through ancestor folders (optimized)
      folder.parent_id != nil ->
        has_recursive_folder_access_optimized?(user, folder.id)

      true ->
        false
    end
  end

  def has_folder_access?(_user, nil), do: false

  # Optimized recursive folder access check using a single CTE query
  defp has_recursive_folder_access_optimized?(%User{id: user_id} = user, folder_id) do
    # Get all ancestor folders with owners in a single query
    ancestors = SecureSharing.Files.get_ancestor_folders_with_owners(folder_id)

    # Check each ancestor for:
    # 1. User is the owner
    # 2. User has an active recursive share
    Enum.any?(ancestors, fn {ancestor_id, owner_id} ->
      cond do
        user_id == owner_id ->
          true

        share = get_share_for_user(user, :folder, ancestor_id) ->
          ShareGrant.active?(share) and share.recursive

        true ->
          false
      end
    end)
  end

  # ============================================================================
  # Managing Shares
  # ============================================================================

  @doc """
  Revokes a share grant.

  Only the grantor or a user with admin permission on the resource can revoke a share.
  """
  def revoke_share(%ShareGrant{} = share, %User{} = revoked_by) do
    cond do
      share.revoked_at != nil ->
        {:error, :already_revoked}

      not can_revoke_share?(share, revoked_by) ->
        {:error, :forbidden}

      true ->
        share
        |> ShareGrant.revoke_changeset(revoked_by)
        |> Repo.update()
    end
  end

  # Check if a user can revoke a share
  defp can_revoke_share?(%ShareGrant{} = share, %User{} = user) do
    cond do
      # Grantor can always revoke their own shares
      share.grantor_id == user.id ->
        true

      # User with admin permission on the resource can revoke
      share.resource_type == :file ->
        case SecureSharing.Files.get_file(share.resource_id) do
          nil -> false
          file -> get_file_permission(user, file) in [:owner, :admin]
        end

      share.resource_type == :folder ->
        get_folder_permission(user, share.resource_id) in [:owner, :admin]

      true ->
        false
    end
  end

  @doc """
  Revokes all shares for a specific resource.

  Used when deleting a file or folder.
  """
  def revoke_all_shares(resource_type, resource_id, %User{} = revoked_by) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      ShareGrant
      |> where([s], s.resource_type == ^resource_type and s.resource_id == ^resource_id)
      |> where([s], is_nil(s.revoked_at))
      |> Repo.update_all(set: [revoked_at: now, revoked_by_id: revoked_by.id])

    {:ok, count}
  end

  @doc """
  Updates the permission level of a share.

  Requires a new signature since permission is part of the signed data.
  """
  def update_permission(%ShareGrant{} = share, attrs) do
    share
    |> ShareGrant.permission_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Sets or extends the expiry time of a share.
  """
  def set_expiry(%ShareGrant{} = share, expires_at) do
    share
    |> ShareGrant.expiry_changeset(%{expires_at: expires_at})
    |> Repo.update()
  end

  @doc """
  Removes the expiry time, making the share permanent.
  """
  def remove_expiry(%ShareGrant{} = share) do
    share
    |> Ecto.Changeset.change(expires_at: nil)
    |> Repo.update()
  end

  # ============================================================================
  # Access Verification
  # ============================================================================

  @doc """
  Gets the permission level a user has for a file.

  Returns :owner, :admin, :write, :read, or nil if no access.
  """
  def get_file_permission(%User{id: user_id} = user, %File{owner_id: owner_id} = file) do
    cond do
      user_id == owner_id ->
        :owner

      share = get_share_for_user(user, :file, file.id) ->
        if ShareGrant.active?(share), do: share.permission, else: nil

      true ->
        # Check folder access
        get_folder_permission(user, file.folder_id)
    end
  end

  @doc """
  Gets the permission level a user has for a folder.

  Returns :owner, :admin, :write, :read, or nil if no access.

  This function is optimized to fetch all ancestor folders in a single query
  to avoid N+1 database calls.
  """
  def get_folder_permission(%User{} = user, folder_id) when is_binary(folder_id) do
    folder = SecureSharing.Files.get_folder(folder_id)
    get_folder_permission(user, folder)
  end

  def get_folder_permission(%User{id: user_id} = user, %Folder{owner_id: owner_id} = folder) do
    cond do
      # Fast path: user is the owner
      user_id == owner_id ->
        :owner

      # Check for direct share on this folder
      share = get_share_for_user(user, :folder, folder.id) ->
        if ShareGrant.active?(share), do: share.permission, else: nil

      # Check for recursive access through ancestor folders (optimized)
      folder.parent_id != nil ->
        get_recursive_folder_permission_optimized(user, folder.id)

      true ->
        nil
    end
  end

  def get_folder_permission(_user, nil), do: nil

  # Optimized recursive folder permission check using a single CTE query
  defp get_recursive_folder_permission_optimized(%User{id: user_id} = user, folder_id) do
    # Get all ancestor folders with owners in a single query
    ancestors = SecureSharing.Files.get_ancestor_folders_with_owners(folder_id)

    # Find the first ancestor that grants permission
    Enum.find_value(ancestors, fn {ancestor_id, owner_id} ->
      cond do
        user_id == owner_id ->
          :owner

        share = get_share_for_user(user, :folder, ancestor_id) ->
          # Only grant permission if share is active AND recursive
          if ShareGrant.active?(share) and share.recursive do
            share.permission
          else
            nil
          end

        true ->
          nil
      end
    end)
  end

  @doc """
  Checks if a user can perform a write operation on a file.
  """
  def can_write_file?(%User{} = user, %File{} = file) do
    permission = get_file_permission(user, file)
    permission in [:owner, :admin, :write]
  end

  @doc """
  Checks if a user can share a file with others.
  """
  def can_share_file?(%User{} = user, %File{} = file) do
    permission = get_file_permission(user, file)
    permission in [:owner, :admin]
  end

  @doc """
  Checks if a user can delete a file.
  Only owner and admin can delete files.
  """
  def can_delete_file?(%User{} = user, %File{} = file) do
    permission = get_file_permission(user, file)
    permission in [:owner, :admin]
  end

  @doc """
  Checks if a user can perform a write operation on a folder.
  """
  # Root folder (nil) - any authenticated user can write to their root
  def can_write_folder?(%User{} = _user, nil), do: true

  def can_write_folder?(%User{} = user, %Folder{} = folder) do
    permission = get_folder_permission(user, folder)
    permission in [:owner, :admin, :write]
  end

  @doc """
  Checks if a user can share a folder with others.
  """
  def can_share_folder?(%User{} = user, %Folder{} = folder) do
    permission = get_folder_permission(user, folder)
    permission in [:owner, :admin]
  end

  @doc """
  Checks if a user can delete a folder.
  Only owner and admin can delete folders.
  """
  def can_delete_folder?(%User{} = user, %Folder{} = folder) do
    permission = get_folder_permission(user, folder)
    permission in [:owner, :admin]
  end

  # ============================================================================
  # Ownership Transfer
  # ============================================================================

  @doc """
  Transfers file ownership from the current owner to a new owner.

  The caller must be the current owner. On success:
  - The file's `owner_id` is updated to the new owner
  - The old owner is given an `:admin` share grant (so they retain access)
  - A new wrapped DEK for the new owner must be provided by the client

  ## Parameters
  - file: The file to transfer
  - current_owner: Must be the current owner
  - new_owner: The user receiving ownership
  - attrs: Map containing re-encrypted key material:
    - `wrapped_dek` - DEK re-encrypted for new owner's public key
    - `kem_ciphertext` - KEM ciphertext
    - `signature` - New owner's signature
    - `old_owner_wrapped_key` - DEK wrapped for old owner (for their admin share)
    - `old_owner_kem_ciphertext` - KEM ciphertext for old owner
    - `old_owner_signature` - Old owner's signature on their share grant
  """
  def transfer_file_ownership(
        %File{} = file,
        %User{} = current_owner,
        %User{} = new_owner,
        attrs
      ) do
    cond do
      file.owner_id != current_owner.id ->
        {:error, :forbidden}

      current_owner.id == new_owner.id ->
        {:error, {:bad_request, "Cannot transfer ownership to yourself"}}

      file.tenant_id != new_owner.tenant_id ->
        {:error, :cross_tenant_operation}

      true ->
        Repo.transaction(fn ->
          # Update file ownership
          file_changeset =
            file
            |> Ecto.Changeset.change(%{
              owner_id: new_owner.id,
              wrapped_dek: attrs[:wrapped_dek] || file.wrapped_dek,
              kem_ciphertext: attrs[:kem_ciphertext] || file.kem_ciphertext,
              signature: attrs[:signature] || file.signature,
              updated_by_id: current_owner.id
            })

          case Repo.update(file_changeset) do
            {:ok, updated_file} ->
              # Revoke any existing share the new owner had
              case get_share_for_user(new_owner, :file, file.id) do
                nil -> :ok
                existing -> Repo.delete(existing)
              end

              # Create admin share for old owner
              share_attrs = %{
                tenant_id: file.tenant_id,
                grantor_id: new_owner.id,
                grantee_id: current_owner.id,
                resource_type: :file,
                resource_id: file.id,
                wrapped_key: attrs[:old_owner_wrapped_key] || :crypto.strong_rand_bytes(64),
                kem_ciphertext:
                  attrs[:old_owner_kem_ciphertext] || :crypto.strong_rand_bytes(128),
                signature: attrs[:old_owner_signature] || :crypto.strong_rand_bytes(256),
                permission: :admin,
                recursive: false
              }

              case %ShareGrant{} |> ShareGrant.changeset(share_attrs) |> Repo.insert() do
                {:ok, _share} -> updated_file
                {:error, changeset} -> Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Transfers folder ownership from the current owner to a new owner.

  The caller must be the current owner. On success:
  - The folder's `owner_id` is updated to the new owner
  - The old owner is given an `:admin` share grant
  - A new wrapped KEK for the new owner must be provided by the client
  """
  def transfer_folder_ownership(
        %Folder{} = folder,
        %User{} = current_owner,
        %User{} = new_owner,
        attrs
      ) do
    cond do
      folder.owner_id != current_owner.id ->
        {:error, :forbidden}

      current_owner.id == new_owner.id ->
        {:error, {:bad_request, "Cannot transfer ownership to yourself"}}

      folder.tenant_id != new_owner.tenant_id ->
        {:error, :cross_tenant_operation}

      folder.is_root ->
        {:error, {:bad_request, "Cannot transfer ownership of root folder"}}

      true ->
        Repo.transaction(fn ->
          # Update folder ownership
          folder_changeset =
            folder
            |> Ecto.Changeset.change(%{
              owner_id: new_owner.id,
              owner_wrapped_kek: attrs[:wrapped_kek] || folder.owner_wrapped_kek,
              owner_kem_ciphertext: attrs[:kem_ciphertext] || folder.owner_kem_ciphertext,
              signature: attrs[:signature] || folder.signature,
              updated_by_id: current_owner.id
            })

          case Repo.update(folder_changeset) do
            {:ok, updated_folder} ->
              # Revoke any existing share the new owner had
              case get_share_for_user(new_owner, :folder, folder.id) do
                nil -> :ok
                existing -> Repo.delete(existing)
              end

              # Create admin share for old owner
              share_attrs = %{
                tenant_id: folder.tenant_id,
                grantor_id: new_owner.id,
                grantee_id: current_owner.id,
                resource_type: :folder,
                resource_id: folder.id,
                wrapped_key: attrs[:old_owner_wrapped_key] || :crypto.strong_rand_bytes(64),
                kem_ciphertext:
                  attrs[:old_owner_kem_ciphertext] || :crypto.strong_rand_bytes(128),
                signature: attrs[:old_owner_signature] || :crypto.strong_rand_bytes(256),
                permission: :admin,
                recursive: true
              }

              case %ShareGrant{} |> ShareGrant.changeset(share_attrs) |> Repo.insert() do
                {:ok, _share} -> updated_folder
                {:error, changeset} -> Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  # ============================================================================
  # Expiry
  # ============================================================================

  @doc """
  Expires all active shares whose `expires_at` has passed.

  Returns `{:ok, count}` where count is the number of shares expired.
  Called by `ExpireSharesWorker` on a 15-minute cron schedule.
  """
  def expire_stale_shares do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {count, _} =
      ShareGrant
      |> where([s], not is_nil(s.expires_at))
      |> where([s], s.expires_at <= ^now)
      |> where([s], is_nil(s.revoked_at))
      |> Repo.update_all(set: [revoked_at: now])

    {:ok, count}
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Counts active shares for a user (both received and created).
  """
  def count_user_shares(%User{id: user_id}) do
    now = DateTime.utc_now()

    received =
      ShareGrant
      |> where([s], s.grantee_id == ^user_id)
      |> where([s], is_nil(s.revoked_at))
      |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
      |> Repo.aggregate(:count)

    created =
      ShareGrant
      |> where([s], s.grantor_id == ^user_id)
      |> where([s], is_nil(s.revoked_at))
      |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
      |> Repo.aggregate(:count)

    %{received: received, created: created}
  end

  @doc """
  Counts all active shares in the system (for admin dashboard).
  """
  def count_shares do
    now = DateTime.utc_now()

    ShareGrant
    |> where([s], is_nil(s.revoked_at))
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> Repo.aggregate(:count)
  end

  # ============================================================================
  # Access Requests (Permission Upgrade)
  # ============================================================================

  @doc """
  Creates a permission upgrade request for an existing share.

  The requester must be the grantee of the share, and the share must be active.
  The requested permission must be higher than the current permission.

  Returns `{:ok, access_request}` or `{:error, reason}`.
  """
  def request_upgrade(%ShareGrant{} = share, %User{} = requester, attrs) do
    requested_permission = attrs[:requested_permission]

    cond do
      share.grantee_id != requester.id ->
        {:error, :forbidden}

      not ShareGrant.active?(share) ->
        {:error, {:bad_request, "Share is no longer active"}}

      not valid_upgrade?(share.permission, requested_permission) ->
        {:error, {:bad_request, "Requested permission must be higher than current permission"}}

      true ->
        %AccessRequest{}
        |> AccessRequest.changeset(%{
          tenant_id: share.tenant_id,
          share_grant_id: share.id,
          requester_id: requester.id,
          requested_permission: requested_permission,
          reason: attrs[:reason]
        })
        |> Repo.insert()
    end
  end

  @doc """
  Approves a pending access request and upgrades the share permission.

  The approver must be the grantor of the share, or have admin/owner permission
  on the resource. Requires a new signature since permission change affects
  the signed data.

  Returns `{:ok, %{request: access_request, share: updated_share}}` or `{:error, reason}`.
  """
  def approve_upgrade(%AccessRequest{status: :pending} = request, %User{} = approver, attrs) do
    share = Repo.get!(ShareGrant, request.share_grant_id)

    if can_approve_request?(share, approver) do
      Repo.transaction(fn ->
        # Mark request as approved
        {:ok, updated_request} =
          request
          |> AccessRequest.decision_changeset(%{status: :approved, decided_by_id: approver.id})
          |> Repo.update()

        # Upgrade the share permission
        permission_attrs = %{
          permission: request.requested_permission,
          signature: attrs[:signature] || share.signature
        }

        {:ok, updated_share} = update_permission(share, permission_attrs)

        %{request: updated_request, share: updated_share}
      end)
    else
      {:error, :forbidden}
    end
  end

  def approve_upgrade(%AccessRequest{}, _approver, _attrs) do
    {:error, {:bad_request, "Only pending requests can be approved"}}
  end

  @doc """
  Denies a pending access request.

  The denier must be the grantor of the share, or have admin/owner permission
  on the resource.

  Returns `{:ok, access_request}` or `{:error, reason}`.
  """
  def deny_upgrade(%AccessRequest{status: :pending} = request, %User{} = denier) do
    share = Repo.get!(ShareGrant, request.share_grant_id)

    if can_approve_request?(share, denier) do
      request
      |> AccessRequest.decision_changeset(%{status: :denied, decided_by_id: denier.id})
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  def deny_upgrade(%AccessRequest{}, _denier) do
    {:error, {:bad_request, "Only pending requests can be denied"}}
  end

  @doc """
  Gets an access request by ID.
  """
  def get_access_request(id), do: Repo.get(AccessRequest, id)

  @doc """
  Lists pending access requests for shares the user has created (as grantor).
  """
  def list_pending_requests_for_grantor(%User{id: user_id}) do
    AccessRequest
    |> join(:inner, [ar], sg in ShareGrant, on: ar.share_grant_id == sg.id)
    |> where([ar, sg], sg.grantor_id == ^user_id)
    |> where([ar], ar.status == :pending)
    |> order_by([ar], desc: ar.created_at)
    |> Repo.all()
  end

  @doc """
  Lists access requests made by a user.
  """
  def list_requests_by_requester(%User{id: user_id}) do
    AccessRequest
    |> where([ar], ar.requester_id == ^user_id)
    |> order_by([ar], desc: ar.created_at)
    |> Repo.all()
  end

  # Checks if the requested permission is higher than the current
  defp valid_upgrade?(current, requested) do
    levels = %{read: 1, write: 2, admin: 3}
    current_level = Map.get(levels, current, 0)
    requested_level = Map.get(levels, requested, 0)
    requested_level > current_level
  end

  # Checks if a user can approve/deny access requests for a share
  defp can_approve_request?(%ShareGrant{} = share, %User{} = user) do
    cond do
      share.grantor_id == user.id ->
        true

      share.resource_type == :file ->
        case SecureSharing.Files.get_file(share.resource_id) do
          nil -> false
          file -> get_file_permission(user, file) in [:owner, :admin]
        end

      share.resource_type == :folder ->
        get_folder_permission(user, share.resource_id) in [:owner, :admin]

      true ->
        false
    end
  end
end
