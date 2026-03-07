# Script to seed admin user for E2E tests
#
# Usage:
#   MIX_ENV=test mix run priv/repo/seeds/e2e_admin_seed.exs
#
# This creates an admin user for Playwright E2E tests.

alias SecureSharing.Repo
alias SecureSharing.Accounts.{User, Tenant, UserTenant}

IO.puts("Seeding E2E admin user...")

# E2E test admin credentials - match the fixture file
admin_email = System.get_env("E2E_ADMIN_EMAIL", "admin@securesharing.test")
admin_password = System.get_env("E2E_ADMIN_PASSWORD", "AdminTestPassword123!")

# Check if admin already exists
case Repo.get_by(User, email: admin_email) do
  nil ->
    # Create admin tenant first
    {:ok, tenant} =
      case Repo.get_by(Tenant, slug: "e2e-admin-tenant") do
        nil ->
          %Tenant{}
          |> Tenant.changeset(%{
            name: "E2E Admin Tenant",
            slug: "e2e-admin-tenant",
            status: :active
          })
          |> Repo.insert()

        existing ->
          {:ok, existing}
      end

    # Create admin user (using admin changeset which doesn't require tenant_id)
    {:ok, user} =
      %User{}
      |> User.admin_registration_changeset(%{
        email: admin_email,
        password: admin_password
      })
      |> Ecto.Changeset.put_change(:display_name, "E2E Admin")
      |> Ecto.Changeset.put_change(:is_admin, true)
      |> Repo.insert()

    # Associate user with tenant
    %UserTenant{}
    |> UserTenant.changeset(%{
      user_id: user.id,
      tenant_id: tenant.id,
      role: :owner
    })
    |> Repo.insert!()

    IO.puts("Created E2E admin user: #{admin_email}")

  existing ->
    IO.puts("E2E admin user already exists: #{existing.email}")
end

# Create some test tenants for E2E tests
test_tenants = [
  %{name: "E2E Test Tenant 1", slug: "e2e-test-1"},
  %{name: "E2E Test Tenant 2", slug: "e2e-test-2"},
  %{name: "E2E Test Tenant 3", slug: "e2e-test-3"}
]

for tenant_attrs <- test_tenants do
  case Repo.get_by(Tenant, slug: tenant_attrs.slug) do
    nil ->
      %Tenant{}
      |> Tenant.changeset(Map.put(tenant_attrs, :status, :active))
      |> Repo.insert!()

      IO.puts("Created tenant: #{tenant_attrs.name}")

    _existing ->
      IO.puts("Tenant already exists: #{tenant_attrs.name}")
  end
end

IO.puts("E2E seed complete!")
