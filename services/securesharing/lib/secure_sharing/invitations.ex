defmodule SecureSharing.Invitations do
  @moduledoc """
  The Invitations context handles the invitation-only onboarding system.

  ## Public API

  ### Creating Invitations
  - `create_invitation/2` - Create a new invitation
  - `can_invite?/2` - Check if a user can send invitations
  - `can_invite_role?/2` - Check if a user can invite with a specific role

  ### Retrieving Invitations
  - `get_invitation/1` - Get invitation by ID
  - `get_invitation_by_token/1` - Get invitation by token (for acceptance)
  - `list_tenant_invitations/2` - List all invitations for a tenant
  - `list_pending_invitations/1` - List pending invitations for a tenant

  ### Managing Invitations
  - `accept_invitation/3` - Accept an invitation and create user
  - `revoke_invitation/1` - Revoke a pending invitation
  - `resend_invitation/1` - Resend invitation email
  - `expire_old_invitations/0` - Expire invitations past their expiry date
  """

  import Ecto.Query
  alias SecureSharing.Repo
  alias SecureSharing.Accounts
  alias SecureSharing.Accounts.{Tenant, User}
  alias SecureSharing.Invitations.Invitation

  # Default invitation expiry: 7 days
  @default_expiry_hours 168

  ## Creating Invitations

  @doc """
  Creates a new invitation.

  ## Params
  - `inviter` - The user creating the invitation
  - `attrs` - Invitation attributes:
    - `:email` - Email address of the invitee (required)
    - `:role` - Role to assign (default: :member)
    - `:message` - Personal message (optional)
    - `:tenant_id` - Tenant ID (required)

  ## Returns
  - `{:ok, invitation}` with the token set on the struct (only available at creation)
  - `{:error, changeset}` if validation fails
  - `{:error, :not_authorized}` if inviter cannot invite
  - `{:error, :email_already_registered}` if email already exists in tenant
  """
  def create_invitation(%User{} = inviter, attrs) do
    tenant_id = attrs[:tenant_id] || attrs["tenant_id"] || inviter.tenant_id
    role = normalize_role(attrs[:role] || attrs["role"] || :member)
    email = normalize_email(attrs[:email] || attrs["email"])

    with :ok <- validate_can_invite(inviter, tenant_id, role),
         :ok <- validate_email_not_registered(email, tenant_id),
         :ok <- validate_no_pending_invitation(email, tenant_id) do
      tenant = Accounts.get_tenant(tenant_id)
      expiry_hours = get_expiry_hours(tenant)
      expires_at = DateTime.utc_now() |> DateTime.add(expiry_hours * 3600, :second)

      invitation_attrs = %{
        email: email,
        role: role,
        message: attrs[:message] || attrs["message"],
        tenant_id: tenant_id,
        inviter_id: inviter.id,
        expires_at: expires_at,
        metadata: attrs[:metadata] || attrs["metadata"] || %{}
      }

      %Invitation{}
      |> Invitation.create_changeset(invitation_attrs)
      |> Repo.insert()
    end
  end

  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role(role) when is_binary(role), do: String.to_existing_atom(role)

  defp normalize_email(email) when is_binary(email), do: String.downcase(String.trim(email))
  defp normalize_email(nil), do: nil

  defp validate_can_invite(inviter, tenant_id, role) do
    if can_invite?(inviter, tenant_id) && can_invite_role?(inviter, role) do
      :ok
    else
      {:error, :not_authorized}
    end
  end

  defp validate_email_not_registered(email, tenant_id) do
    if Accounts.get_user_by_email(tenant_id, email) do
      {:error, :email_already_registered}
    else
      :ok
    end
  end

  defp validate_no_pending_invitation(email, tenant_id) do
    if get_pending_invitation_for_email(email, tenant_id) do
      {:error, :pending_invitation_exists}
    else
      :ok
    end
  end

  defp get_expiry_hours(nil), do: @default_expiry_hours

  defp get_expiry_hours(%Tenant{} = _tenant) do
    # Could read from tenant.invitation_settings in the future
    @default_expiry_hours
  end

  @doc """
  Check if a user can send invitations in a tenant.
  """
  def can_invite?(%User{} = user, tenant_id) do
    # Platform admins can always invite
    if user.is_admin do
      true
    else
      # Check user's role in the tenant
      role = Accounts.get_user_role_in_tenant(user.id, tenant_id)
      role in [:admin, :owner]
    end
  end

  @doc """
  Check if a user can invite someone with a specific role.

  Role hierarchy:
  - admin/owner can invite: admin, manager, member
  - manager can invite: member only
  - member cannot invite
  """
  def can_invite_role?(%User{is_admin: true}, _role), do: true

  def can_invite_role?(%User{role: inviter_role}, target_role) do
    role_level = %{owner: 4, admin: 3, manager: 2, member: 1}
    inviter_level = Map.get(role_level, inviter_role, 1)
    target_level = Map.get(role_level, target_role, 1)

    inviter_level >= target_level
  end

  ## Retrieving Invitations

  @doc """
  Get an invitation by ID.
  """
  def get_invitation(id) do
    Invitation
    |> Repo.get(id)
    |> Repo.preload([:tenant, :inviter])
  end

  @doc """
  Get an invitation by ID, raises if not found.
  """
  def get_invitation!(id) do
    Invitation
    |> Repo.get!(id)
    |> Repo.preload([:tenant, :inviter])
  end

  @doc """
  Get an invitation by token (for the acceptance flow).

  Returns the invitation with tenant and inviter preloaded, or nil if not found.
  """
  def get_invitation_by_token(token) when is_binary(token) do
    token_hash = Invitation.hash_token(token)

    Invitation
    |> where([i], i.token_hash == ^token_hash)
    |> Repo.one()
    |> Repo.preload([:tenant, :inviter])
  end

  @doc """
  Get a pending invitation for an email in a tenant.
  """
  def get_pending_invitation_for_email(email, tenant_id) do
    email = normalize_email(email)

    Invitation
    |> where([i], i.email == ^email and i.tenant_id == ^tenant_id and i.status == :pending)
    |> Repo.one()
  end

  @doc """
  List all invitations for a tenant.

  ## Options
  - `:status` - Filter by status (default: all)
  - `:limit` - Limit results
  - `:offset` - Offset for pagination
  """
  def list_tenant_invitations(tenant_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Invitation
    |> where([i], i.tenant_id == ^tenant_id)
    |> maybe_filter_status(status)
    |> order_by([i], desc: i.created_at)
    |> maybe_limit(limit)
    |> offset(^offset)
    |> preload([:inviter, :accepted_by])
    |> Repo.all()
  end

  @doc """
  List pending invitations for a tenant.
  """
  def list_pending_invitations(tenant_id) do
    list_tenant_invitations(tenant_id, status: :pending)
  end

  @doc """
  List all invitations across all tenants (admin only).

  ## Options
  - `:status` - Filter by status (pending, accepted, expired, revoked)
  - `:limit` - Limit results
  - `:offset` - Offset for pagination
  """
  def list_all_invitations(opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Invitation
    |> maybe_filter_status(status)
    |> order_by([i], desc: i.created_at)
    |> maybe_limit(limit)
    |> offset(^offset)
    |> preload([:inviter, :accepted_by, :tenant])
    |> Repo.all()
  end

  @doc """
  Count invitations for a tenant by status.
  """
  def count_invitations(tenant_id, status \\ nil) do
    Invitation
    |> where([i], i.tenant_id == ^tenant_id)
    |> maybe_filter_status(status)
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [i], i.status == ^status)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  ## Managing Invitations

  @doc """
  Accept an invitation and create a new user.

  ## Params
  - `token` - The invitation token from the URL
  - `user_attrs` - User registration attributes:
    - `:display_name` - User's display name
    - `:password` - User's password
    - `:public_keys` - PQC public keys
    - `:encrypted_private_keys` - Encrypted private keys
    - `:encrypted_master_key` - Encrypted master key
    - `:key_derivation_salt` - Key derivation salt

  ## Returns
  - `{:ok, user}` if successful
  - `{:error, :invitation_not_found}` if token is invalid
  - `{:error, :invitation_expired}` if invitation is past expiry
  - `{:error, :invitation_revoked}` if invitation was revoked
  - `{:error, :invitation_already_used}` if already accepted
  - `{:error, changeset}` if user creation fails
  """
  def accept_invitation(token, user_attrs) do
    case get_invitation_by_token(token) do
      nil ->
        {:error, :invitation_not_found}

      %Invitation{status: :accepted} ->
        {:error, :invitation_already_used}

      %Invitation{status: :revoked} ->
        {:error, :invitation_revoked}

      %Invitation{status: :expired} ->
        {:error, :invitation_expired}

      %Invitation{status: :pending} = invitation ->
        if Invitation.valid?(invitation) do
          do_accept_invitation(invitation, user_attrs)
        else
          # Mark as expired if past expiry date
          invitation
          |> Invitation.expire_changeset()
          |> Repo.update()

          {:error, :invitation_expired}
        end
    end
  end

  defp do_accept_invitation(invitation, user_attrs) do
    Repo.transaction(fn ->
      # Build user registration attributes
      registration_attrs = %{
        email: invitation.email,
        password: user_attrs[:password] || user_attrs["password"],
        display_name: user_attrs[:display_name] || user_attrs["display_name"],
        tenant_id: invitation.tenant_id,
        public_keys: user_attrs[:public_keys] || user_attrs["public_keys"] || %{},
        encrypted_private_keys:
          decode_binary(
            user_attrs[:encrypted_private_keys] || user_attrs["encrypted_private_keys"]
          ),
        encrypted_master_key:
          decode_binary(user_attrs[:encrypted_master_key] || user_attrs["encrypted_master_key"]),
        key_derivation_salt:
          decode_binary(user_attrs[:key_derivation_salt] || user_attrs["key_derivation_salt"])
      }

      # Create the user
      case Accounts.register_user(registration_attrs) do
        {:ok, user} ->
          # Add user to tenant with the invited role
          case Accounts.add_user_to_tenant(user.id, invitation.tenant_id, role: invitation.role) do
            {:ok, _user_tenant} ->
              # Mark invitation as accepted
              case invitation
                   |> Invitation.accept_changeset(user.id)
                   |> Repo.update() do
                {:ok, _invitation} -> user
                {:error, changeset} -> Repo.rollback(changeset)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  @doc """
  Revoke a pending invitation.
  """
  def revoke_invitation(%Invitation{status: :pending} = invitation) do
    invitation
    |> Invitation.revoke_changeset()
    |> Repo.update()
  end

  def revoke_invitation(%Invitation{}), do: {:error, :cannot_revoke}

  @doc """
  Revoke an invitation by ID.
  """
  def revoke_invitation_by_id(id) do
    case get_invitation(id) do
      nil -> {:error, :not_found}
      invitation -> revoke_invitation(invitation)
    end
  end

  @doc """
  Resend an invitation email.

  Generates a new token and updates the expiry date.
  """
  def resend_invitation(%Invitation{status: :pending} = invitation) do
    tenant = Accounts.get_tenant(invitation.tenant_id)
    expiry_hours = get_expiry_hours(tenant)
    expires_at = DateTime.utc_now() |> DateTime.add(expiry_hours * 3600, :second)

    # Generate new token
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = Invitation.hash_token(token)

    case invitation
         |> Ecto.Changeset.change(%{token_hash: token_hash, expires_at: expires_at})
         |> Repo.update() do
      {:ok, updated_invitation} ->
        # Return invitation with the new token set for email sending
        {:ok, %{updated_invitation | token: token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def resend_invitation(%Invitation{}), do: {:error, :cannot_resend}

  @doc """
  Expire all pending invitations that are past their expiry date.

  Called by a scheduled job.
  """
  def expire_old_invitations do
    now = DateTime.utc_now()

    {count, _} =
      Invitation
      |> where([i], i.status == :pending and i.expires_at < ^now)
      |> Repo.update_all(set: [status: :expired, updated_at: now])

    {:ok, count}
  end

  @doc """
  Get invitation info for the public API.

  Returns a map with invitation details suitable for the acceptance screen.
  """
  def get_invitation_info(token) do
    case get_invitation_by_token(token) do
      nil ->
        {:error, :not_found}

      invitation ->
        validity = determine_validity(invitation)

        info = %{
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          tenant_name: invitation.tenant.name,
          inviter_name: invitation.inviter.display_name || invitation.inviter.email,
          message: invitation.message,
          expires_at: invitation.expires_at,
          valid: validity == :valid,
          error_reason: if(validity != :valid, do: validity, else: nil)
        }

        {:ok, info}
    end
  end

  defp determine_validity(%Invitation{status: :pending} = invitation) do
    if Invitation.valid?(invitation), do: :valid, else: :expired
  end

  defp determine_validity(%Invitation{status: :accepted}), do: :already_used
  defp determine_validity(%Invitation{status: :expired}), do: :expired
  defp determine_validity(%Invitation{status: :revoked}), do: :revoked
end
