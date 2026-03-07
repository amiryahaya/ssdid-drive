defmodule SecureSharing.Accounts do
  @moduledoc """
  The Accounts context handles user and tenant management.

  ## Public API

  ### Tenants
  - `create_tenant/1` - Create a new tenant
  - `get_tenant/1` - Get tenant by ID
  - `get_tenant_by_slug/1` - Get tenant by slug

  ### Users
  - `register_user/1` - Register a new user
  - `get_user/1` - Get user by ID
  - `get_user_by_email/2` - Get user by tenant and email
  - `authenticate_user/2` - Authenticate with email/password
  - `get_key_bundle/1` - Get user's encrypted key material

  ### Multi-Tenant Users
  - `get_user_tenants/1` - Get all tenants a user belongs to
  - `get_user_tenant/2` - Get user's membership in a specific tenant
  - `add_user_to_tenant/3` - Add a user to a tenant
  - `remove_user_from_tenant/2` - Remove user from tenant
  - `update_user_role_in_tenant/3` - Update user's role in a tenant
  """

  import Ecto.Query
  alias SecureSharing.Repo
  alias SecureSharing.Accounts.{Tenant, User, UserTenant}

  ## Tenants

  @doc """
  Creates a new tenant.

  ## Examples

      iex> create_tenant(%{name: "Acme Corp", slug: "acme-corp"})
      {:ok, %Tenant{}}

      iex> create_tenant(%{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a tenant by ID.
  """
  def get_tenant(id) do
    Repo.get(Tenant, id)
  end

  @doc """
  Gets a tenant by slug.
  """
  def get_tenant_by_slug(slug) do
    Repo.get_by(Tenant, slug: slug)
  end

  ## Users

  @doc """
  Registers a new user.

  ## Params
  - `:email` - User's email address
  - `:password` - User's password (min 12 chars)
  - `:tenant_id` - Tenant ID
  - `:public_keys` - Map of public keys (from client)
  - `:encrypted_private_keys` - Encrypted private keys blob (from client)
  - `:encrypted_master_key` - Encrypted master key blob (from client)
  - `:key_derivation_salt` - Salt for key derivation (from client)

  ## Examples

      iex> register_user(%{email: "user@example.com", password: "secure_password", tenant_id: tenant.id})
      {:ok, %User{}}
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a user by ID, raises if not found.
  """
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @doc """
  Gets a user by DID.
  """
  def get_user_by_did(did) when is_binary(did) do
    Repo.get_by(User, did: did)
  end

  @doc """
  Creates a user account from a DID (auto-provisioned on first SSDID registration).

  Creates a default personal tenant for the user.
  """
  def create_user_from_did(did, attrs \\ %{}) do
    Repo.transaction(fn ->
      # Create a default personal tenant for the new user
      tenant_slug = "personal-" <> String.slice(did, -8, 8)

      {:ok, tenant} =
        create_tenant(%{
          name: attrs[:display_name] || "Personal",
          slug: tenant_slug
        })

      user_attrs =
        Map.merge(attrs, %{
          did: did,
          tenant_id: tenant.id,
          display_name: attrs[:display_name]
        })

      case %User{}
           |> User.did_registration_changeset(user_attrs)
           |> Repo.insert() do
        {:ok, user} ->
          # Add user as owner of their personal tenant
          add_user_to_tenant(user.id, tenant.id, :owner)
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Gets a user's default tenant (first tenant they belong to).
  """
  def get_default_tenant(%User{} = user) do
    case get_user_tenants(user.id) do
      [first | _] -> get_tenant(first.id)
      [] -> get_tenant(user.tenant_id)
    end
  end

  @doc """
  Records login activity for a user.
  """
  def record_login(%User{} = user) do
    user
    |> User.login_changeset()
    |> Repo.update()
  end

  @doc """
  Gets a user's encrypted key bundle for client-side decryption.

  The bundle includes all encrypted keys needed to derive the Master Key
  and decrypt the user's private keys.

  ## Returns
  - `:encrypted_master_key` - MK encrypted with password-derived key
  - `:encrypted_private_keys` - Private keys encrypted with MK
  - `:key_derivation_salt` - Salt for Argon2id key derivation
  - `:public_keys` - Public keys (not encrypted)
  """
  def get_key_bundle(%User{} = user) do
    {:ok,
     %{
       encrypted_master_key: user.encrypted_master_key,
       encrypted_private_keys: user.encrypted_private_keys,
       key_derivation_salt: user.key_derivation_salt,
       public_keys: user.public_keys
     }}
  end

  @doc """
  Updates a user's key material.

  Used after password change or recovery to re-encrypt keys.
  """
  def update_key_material(%User{} = user, attrs) do
    user
    |> User.key_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all users for a tenant.
  """
  def list_users(tenant_id) do
    User
    |> where([u], u.tenant_id == ^tenant_id)
    |> Repo.all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.did_registration_changeset(user, attrs)
  end

  ## Admin Functions

  @doc """
  Checks if any admin user exists in the system.

  Used to determine if the bootstrap setup page should be accessible.
  """
  @spec admin_exists?() :: boolean()
  def admin_exists? do
    User
    |> where([u], u.is_admin == true)
    |> Repo.exists?()
  end

  @doc """
  Creates the first admin user during system bootstrap.

  Unlike regular registration, this:
  - Sets is_admin to true
  - Auto-confirms the email
  - Does not require a tenant_id
  """
  @spec create_admin_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_admin_user(attrs) do
    %User{}
    |> User.admin_registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:is_admin, true)
    |> Repo.insert()
  end

  @doc """
  Counts total number of tenants.
  """
  def count_tenants do
    Repo.aggregate(Tenant, :count, :id)
  end

  @doc """
  Counts total number of users.
  """
  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  @doc """
  Lists all tenants with optional pagination.
  """
  def list_tenants(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Tenant
    |> order_by([t], desc: t.created_at)
    |> maybe_limit(limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Lists recent tenants for dashboard.
  """
  def list_recent_tenants(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    Tenant
    |> order_by([t], desc: t.created_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists all users across all tenants with optional pagination.
  """
  def list_all_users(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> order_by([u], desc: u.created_at)
    |> preload(:tenant)
    |> maybe_limit(limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Searches users by email or display name.
  """
  def search_users(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    search_term = "%#{query}%"

    User
    |> where([u], ilike(u.email, ^search_term) or ilike(u.display_name, ^search_term))
    |> where([u], u.status == :active)
    |> order_by([u], asc: u.email)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists recent users for dashboard.
  """
  def list_recent_users(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    User
    |> order_by([u], desc: u.created_at)
    |> preload(:tenant)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Updates a user's status.
  """
  def update_user_status(%User{} = user, status) do
    user
    |> User.status_changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Updates a user's profile (display name).
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's admin status.
  """
  def set_admin(%User{} = user, is_admin) when is_boolean(is_admin) do
    user
    |> User.admin_changeset(%{is_admin: is_admin})
    |> Repo.update()
  end

  @doc """
  Updates a tenant.
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tenant.
  """
  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  ## Multi-Tenant User Functions

  @doc """
  Gets all tenants a user belongs to, with their roles.

  Returns a list of maps with tenant info and user's role in each.
  """
  def get_user_tenants(user_id) do
    UserTenant
    |> where([ut], ut.user_id == ^user_id and ut.status == "active")
    |> join(:inner, [ut], t in Tenant, on: ut.tenant_id == t.id)
    |> select([ut, t], %{
      id: t.id,
      name: t.name,
      slug: t.slug,
      role: ut.role,
      joined_at: ut.joined_at
    })
    |> order_by([ut, t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Gets all tenants a user belongs to, preloading full tenant data.
  """
  def get_user_tenants_full(user_id) do
    UserTenant
    |> where([ut], ut.user_id == ^user_id and ut.status == "active")
    |> preload(:tenant)
    |> Repo.all()
  end

  @doc """
  Gets a user's membership record for a specific tenant.

  Returns nil if user doesn't belong to the tenant.
  """
  def get_user_tenant(user_id, tenant_id) do
    UserTenant
    |> where([ut], ut.user_id == ^user_id and ut.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  @doc """
  Checks if a user belongs to a tenant.
  """
  def user_belongs_to_tenant?(user_id, tenant_id) do
    UserTenant
    |> where(
      [ut],
      ut.user_id == ^user_id and ut.tenant_id == ^tenant_id and ut.status == "active"
    )
    |> Repo.exists?()
  end

  @doc """
  Gets a user's role in a specific tenant.

  Returns nil if user doesn't belong to the tenant.
  """
  def get_user_role_in_tenant(user_id, tenant_id) do
    UserTenant
    |> where(
      [ut],
      ut.user_id == ^user_id and ut.tenant_id == ^tenant_id and ut.status == "active"
    )
    |> select([ut], ut.role)
    |> Repo.one()
  end

  @doc """
  Adds a user to a tenant with the specified role.

  ## Options
  - `:role` - User's role in the tenant (default: :member)
  - `:invited_by_id` - ID of the user who sent the invitation
  - `:status` - Initial status (default: "active", use "pending" for invitations)
  """
  def add_user_to_tenant(user_id, tenant_id, opts \\ []) do
    attrs = %{
      user_id: user_id,
      tenant_id: tenant_id,
      role: Keyword.get(opts, :role, :member),
      invited_by_id: Keyword.get(opts, :invited_by_id),
      status: Keyword.get(opts, :status, "active")
    }

    %UserTenant{}
    |> UserTenant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Invites a user to a tenant. Creates a pending membership.
  """
  def invite_user_to_tenant(user_id, tenant_id, invited_by_id, role \\ :member) do
    attrs = %{
      user_id: user_id,
      tenant_id: tenant_id,
      role: role,
      invited_by_id: invited_by_id
    }

    %UserTenant{}
    |> UserTenant.invitation_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Accepts a pending tenant invitation.
  """
  def accept_tenant_invitation(user_id, tenant_id) do
    case get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :not_found}

      %UserTenant{status: "pending"} = user_tenant ->
        user_tenant
        |> UserTenant.accept_invitation_changeset()
        |> Repo.update()

      %UserTenant{status: "active"} ->
        {:error, :already_accepted}

      _ ->
        {:error, :invalid_status}
    end
  end

  @doc """
  Declines a pending tenant invitation.
  """
  def decline_tenant_invitation(user_id, tenant_id) do
    case get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :not_found}

      %UserTenant{status: "pending"} = user_tenant ->
        Repo.delete(user_tenant)

      _ ->
        {:error, :invalid_status}
    end
  end

  @doc """
  Gets a user_tenant record by its ID.
  """
  def get_user_tenant_by_id(id) do
    UserTenant
    |> Repo.get(id)
    |> Repo.preload([:tenant, :user])
  end

  @doc """
  Gets all pending invitations for a user.
  """
  def get_pending_invitations(user_id) do
    UserTenant
    |> where([ut], ut.user_id == ^user_id and ut.status == "pending")
    |> join(:inner, [ut], t in Tenant, on: ut.tenant_id == t.id)
    |> join(:left, [ut, t], inviter in User, on: ut.invited_by_id == inviter.id)
    |> select([ut, t, inviter], %{
      id: ut.id,
      tenant_id: t.id,
      tenant_name: t.name,
      tenant_slug: t.slug,
      role: ut.role,
      invited_by_id: ut.invited_by_id,
      invited_by_email: inviter.email,
      invited_by_name: inviter.display_name,
      invited_at: ut.created_at
    })
    |> order_by([ut, t, inviter], desc: ut.created_at)
    |> Repo.all()
  end

  @doc """
  Removes a user from a tenant.
  """
  def remove_user_from_tenant(user_id, tenant_id) do
    case get_user_tenant(user_id, tenant_id) do
      nil -> {:error, :not_found}
      user_tenant -> Repo.delete(user_tenant)
    end
  end

  @doc """
  Updates a user's role in a tenant.
  """
  def update_user_role_in_tenant(user_id, tenant_id, new_role) do
    case get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :not_found}

      user_tenant ->
        case user_tenant
             |> UserTenant.role_changeset(new_role)
             |> Repo.update() do
          {:ok, updated} ->
            # Preload user for JSON rendering
            {:ok, Repo.preload(updated, :user)}

          error ->
            error
        end
    end
  end

  @doc """
  Lists all members of a tenant with their roles.
  """
  def list_tenant_members(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")

    UserTenant
    |> where([ut], ut.tenant_id == ^tenant_id)
    |> maybe_filter_by_status(status)
    |> join(:inner, [ut], u in User, on: ut.user_id == u.id)
    |> select([ut, u], %{
      user_id: u.id,
      email: u.email,
      display_name: u.display_name,
      role: ut.role,
      status: ut.status,
      joined_at: ut.joined_at
    })
    |> order_by([ut, u], asc: u.email)
    |> Repo.all()
  end

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status), do: where(query, [ut], ut.status == ^status)

  @doc """
  Gets the default tenant for a user (first one they joined).
  """
  def get_default_tenant(user_id) do
    UserTenant
    |> where([ut], ut.user_id == ^user_id and ut.status == "active")
    |> order_by([ut], asc: ut.joined_at)
    |> limit(1)
    |> preload(:tenant)
    |> Repo.one()
    |> case do
      nil -> nil
      user_tenant -> user_tenant.tenant
    end
  end

  @doc """
  Creates a user and adds them to a tenant in a single transaction.

  This is used during registration to ensure both records are created atomically.
  """
  def register_user_with_tenant(attrs, tenant_id, role \\ :member) do
    Repo.transaction(fn ->
      # Create the user
      case register_user(attrs) do
        {:ok, user} ->
          # Add user to tenant
          case add_user_to_tenant(user.id, tenant_id, role: role) do
            {:ok, _user_tenant} -> user
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end
end
