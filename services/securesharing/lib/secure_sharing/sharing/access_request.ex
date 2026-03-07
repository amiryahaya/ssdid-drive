defmodule SecureSharing.Sharing.AccessRequest do
  @moduledoc """
  Schema for permission upgrade requests on share grants.

  When a user has `:read` access to a file or folder, they can request
  an upgrade to `:write` or `:admin` from the resource owner or an admin.
  The owner/admin can then approve or deny the request.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.{Tenant, User}
  alias SecureSharing.Sharing.ShareGrant

  @statuses [:pending, :approved, :denied]
  @requestable_permissions [:write, :admin]

  schema "access_requests" do
    belongs_to :tenant, Tenant
    belongs_to :share_grant, ShareGrant
    belongs_to :requester, User
    belongs_to :decided_by, User

    field :requested_permission, Ecto.Enum, values: @requestable_permissions
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :reason, :string
    field :decided_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new access request.
  """
  def changeset(access_request, attrs) do
    access_request
    |> cast(attrs, [
      :tenant_id,
      :share_grant_id,
      :requester_id,
      :requested_permission,
      :reason
    ])
    |> validate_required([
      :tenant_id,
      :share_grant_id,
      :requester_id,
      :requested_permission
    ])
    |> validate_inclusion(:requested_permission, @requestable_permissions)
    |> validate_length(:reason, max: 500)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:share_grant_id)
    |> foreign_key_constraint(:requester_id)
    |> unique_constraint([:share_grant_id],
      name: :access_requests_one_pending_per_share,
      message: "a pending upgrade request already exists for this share"
    )
  end

  @doc """
  Changeset for approving or denying a request.
  """
  def decision_changeset(access_request, %{status: status, decided_by_id: decided_by_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    access_request
    |> change(%{
      status: status,
      decided_by_id: decided_by_id,
      decided_at: now
    })
    |> validate_inclusion(:status, [:approved, :denied])
  end
end
