defmodule SecureSharing.Accounts.Tenant do
  @moduledoc """
  Tenant schema for multi-tenant isolation.

  Each tenant represents an organization with isolated data.
  Users can belong to multiple tenants via the `user_tenants` junction table.

  ## PQC Algorithm Selection

  Tenants can choose their post-quantum cryptography algorithm suite:

  - `:kaz` - KAZ-KEM + KAZ-SIGN (Malaysian algorithms)
  - `:nist` - ML-KEM + ML-DSA (NIST FIPS 203/204)
  - `:hybrid` - Both KAZ and NIST combined for defense in depth
  """
  use SecureSharing.Schema

  @pqc_algorithms [:kaz, :nist, :hybrid]
  @tenant_statuses ~w(active suspended deleted)a
  @tenant_plans ~w(free pro enterprise)a

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, Ecto.Enum, values: @tenant_statuses, default: :active
    field :plan, Ecto.Enum, values: @tenant_plans, default: :free
    field :storage_quota_bytes, :integer, default: 10_737_418_240
    field :max_users, :integer, default: 100
    field :settings, :map, default: %{}
    field :pqc_algorithm, Ecto.Enum, values: @pqc_algorithms, default: :kaz

    # Billing
    field :billing_email, :string
    field :stripe_customer_id, :string

    # Legacy: Direct user relationship (deprecated, use user_tenants instead)
    has_many :users, SecureSharing.Accounts.User

    # Multi-tenant support: Tenant can have multiple users
    has_many :user_tenants, SecureSharing.Accounts.UserTenant
    has_many :members, through: [:user_tenants, :user]

    has_many :idp_configs, SecureSharing.Accounts.IdpConfig

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the list of valid PQC algorithm options.
  """
  def pqc_algorithms, do: @pqc_algorithms

  @doc """
  Returns the list of valid tenant statuses.
  """
  def tenant_statuses, do: @tenant_statuses

  @doc """
  Returns the list of valid tenant plans.
  """
  def tenant_plans, do: @tenant_plans

  @doc """
  Changeset for creating a new tenant.
  """
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :name,
      :slug,
      :status,
      :plan,
      :storage_quota_bytes,
      :max_users,
      :settings,
      :pqc_algorithm,
      :billing_email,
      :stripe_customer_id
    ])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with dashes"
    )
    |> validate_length(:slug, min: 2, max: 50)
    |> validate_length(:billing_email, max: 256)
    |> validate_length(:stripe_customer_id, max: 256)
    |> validate_inclusion(:pqc_algorithm, @pqc_algorithms)
    |> validate_inclusion(:status, @tenant_statuses)
    |> validate_inclusion(:plan, @tenant_plans)
    |> unique_constraint(:slug)
  end
end
