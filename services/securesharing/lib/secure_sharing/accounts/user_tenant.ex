defmodule SecureSharing.Accounts.UserTenant do
  @moduledoc """
  Junction table schema for multi-tenant user support.

  Enables users to belong to multiple tenants with per-tenant roles.
  This replaces the direct user-tenant relationship for more flexibility.

  ## Role Hierarchy

  - `:member` - Regular user, can view/edit own files
  - `:admin` - Can manage users and settings for the tenant
  - `:owner` - Full control, including billing and tenant deletion

  ## Status

  - `active` - Normal access to tenant
  - `suspended` - Access temporarily revoked
  - `pending` - Invitation sent but not yet accepted
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.{User, Tenant}

  @user_roles ~w(member admin owner)a
  @statuses ~w(active suspended pending)

  schema "user_tenants" do
    belongs_to :user, User
    belongs_to :tenant, Tenant
    belongs_to :invited_by, User

    field :role, Ecto.Enum, values: @user_roles, default: :member
    field :status, :string, default: "active"
    field :joined_at, :utc_datetime_usec
    field :invitation_accepted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the list of valid user roles.
  """
  def user_roles, do: @user_roles

  @doc """
  Returns the list of valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Changeset for creating a new user-tenant association.
  """
  def changeset(user_tenant, attrs) do
    user_tenant
    |> cast(attrs, [
      :user_id,
      :tenant_id,
      :role,
      :status,
      :invited_by_id,
      :joined_at,
      :invitation_accepted_at
    ])
    |> validate_required([:user_id, :tenant_id])
    |> validate_inclusion(:role, @user_roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :tenant_id], message: "user already belongs to this tenant")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
    |> set_joined_at()
  end

  @doc """
  Changeset for inviting a user to a tenant.
  """
  def invitation_changeset(user_tenant, attrs) do
    user_tenant
    |> cast(attrs, [:user_id, :tenant_id, :role, :invited_by_id])
    |> validate_required([:user_id, :tenant_id, :invited_by_id])
    |> validate_inclusion(:role, @user_roles)
    |> put_change(:status, "pending")
    |> unique_constraint([:user_id, :tenant_id], message: "user already belongs to this tenant")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
    |> set_joined_at()
  end

  @doc """
  Changeset for accepting an invitation.
  """
  def accept_invitation_changeset(user_tenant) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    user_tenant
    |> change(status: "active", invitation_accepted_at: now)
  end

  @doc """
  Changeset for updating role.
  """
  def role_changeset(user_tenant, role) do
    user_tenant
    |> change(role: role)
    |> validate_inclusion(:role, @user_roles)
  end

  @doc """
  Changeset for updating status.
  """
  def status_changeset(user_tenant, status) do
    user_tenant
    |> change(status: status)
    |> validate_inclusion(:status, @statuses)
  end

  defp set_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      put_change(changeset, :joined_at, now)
    end
  end
end
