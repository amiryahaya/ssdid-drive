defmodule SecureSharing.Repo.Migrations.AddTenantStatusAndPlan do
  @moduledoc """
  Adds status, plan, and billing fields to tenants table.

  Matches 02-database-schema.md Section 4.1.
  """
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :status, :tenant_status, null: false, default: "active"
      add :plan, :tenant_plan, null: false, default: "free"
      add :billing_email, :string, size: 256
      add :stripe_customer_id, :string, size: 256
    end

    create index(:tenants, [:status])
  end
end
