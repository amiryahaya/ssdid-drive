defmodule SecureSharing.Audit.AuditEvent do
  @moduledoc """
  Schema for audit events tracking all security-relevant actions in the system.

  Each event captures:
  - Who performed the action (user_id, tenant_id)
  - What action was performed (action)
  - What resource was affected (resource_type, resource_id)
  - Request context (ip_address, user_agent)
  - Additional details (metadata)
  - Outcome (status, error_message)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(
    user.register user.login user.logout user.login_failed
    user.password_change user.profile_update user.delete
    file.create file.read file.update file.delete file.download file.move
    folder.create folder.read folder.update folder.delete folder.move
    share.create share.update share.revoke share.accept
    recovery.setup recovery.share_create recovery.share_accept
    recovery.request recovery.approve recovery.complete
    tenant.create tenant.update tenant.delete
    admin.login admin.logout admin.action
  )

  @resource_types ~w(user file folder share recovery_config recovery_request tenant system)

  @statuses ~w(success failure)

  schema "audit_events" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :ip_address, :string
    field :user_agent, :string
    field :metadata, :map, default: %{}
    field :status, :string, default: "success"
    field :error_message, :string

    belongs_to :tenant, SecureSharing.Accounts.Tenant
    belongs_to :user, SecureSharing.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Creates a changeset for an audit event.
  """
  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [
      :tenant_id,
      :user_id,
      :action,
      :resource_type,
      :resource_id,
      :ip_address,
      :user_agent,
      :metadata,
      :status,
      :error_message
    ])
    |> validate_required([:tenant_id, :action, :resource_type, :status])
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:resource_type, @resource_types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid actions.
  """
  def valid_actions, do: @actions

  @doc """
  Returns the list of valid resource types.
  """
  def valid_resource_types, do: @resource_types

  @doc """
  Returns the list of valid statuses.
  """
  def valid_statuses, do: @statuses
end
