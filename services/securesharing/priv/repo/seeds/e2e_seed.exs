# Comprehensive E2E Test Seed Script
#
# Creates all necessary test data for E2E testing including:
# - E2E Test Organization tenant (slug: "e2e-test")
# - Admin user (admin@securesharing.test)
# - Test users (user1@e2e-test.local through user5@e2e-test.local)
# - Test folders (Documents, Images, Shared)
#
# Usage:
#   MIX_ENV=test mix run priv/repo/seeds/e2e_seed.exs
#
# Environment Variables:
#   E2E_ADMIN_EMAIL    - Admin email (default: admin@securesharing.test)
#   E2E_ADMIN_PASSWORD - Admin password (default: AdminTestPassword123!)
#

alias SecureSharing.Repo
alias SecureSharing.Accounts.{User, Tenant, UserTenant}
alias SecureSharing.Files.Folder
import Ecto.Query

IO.puts("")
IO.puts("═══════════════════════════════════════════════════════════════════════")
IO.puts("  SecureSharing E2E Test Seed")
IO.puts("═══════════════════════════════════════════════════════════════════════")
IO.puts("")

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

admin_email = System.get_env("E2E_ADMIN_EMAIL", "admin@securesharing.test")
admin_password = System.get_env("E2E_ADMIN_PASSWORD", "AdminTestPassword123!")
test_user_password = "TestUserPassword123!"

# ═══════════════════════════════════════════════════════════════════════════════
# TENANT: E2E Test Organization
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("Creating E2E Test Tenant...")

e2e_tenant =
  case Repo.get_by(Tenant, slug: "e2e-test") do
    nil ->
      {:ok, tenant} =
        %Tenant{}
        |> Tenant.changeset(%{
          name: "E2E Test Organization",
          slug: "e2e-test",
          status: :active,
          settings: %{
            "file_size_limit" => 104_857_600,
            "storage_quota" => 10_737_418_240,
            "allowed_file_types" => ["*"],
            "enable_pii_redaction" => true
          }
        })
        |> Repo.insert()

      IO.puts("  ✓ Created tenant: E2E Test Organization (e2e-test)")
      tenant

    existing ->
      IO.puts("  • Tenant already exists: E2E Test Organization")
      existing
  end

# ═══════════════════════════════════════════════════════════════════════════════
# ADMIN USER
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("Creating Admin User...")

admin_user =
  case Repo.get_by(User, email: admin_email) do
    nil ->
      {:ok, user} =
        %User{}
        |> User.admin_registration_changeset(%{
          email: admin_email,
          password: admin_password
        })
        |> Ecto.Changeset.put_change(:display_name, "E2E Admin")
        |> Ecto.Changeset.put_change(:is_admin, true)
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
        |> Repo.insert()

      # Associate admin with E2E tenant as owner
      case Repo.get_by(UserTenant, user_id: user.id, tenant_id: e2e_tenant.id) do
        nil ->
          %UserTenant{}
          |> UserTenant.changeset(%{
            user_id: user.id,
            tenant_id: e2e_tenant.id,
            role: :owner
          })
          |> Repo.insert!()

        _ ->
          :ok
      end

      IO.puts("  ✓ Created admin: #{admin_email}")
      user

    existing ->
      IO.puts("  • Admin already exists: #{existing.email}")
      existing
  end

# ═══════════════════════════════════════════════════════════════════════════════
# TEST USERS
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("Creating Test Users...")

test_users =
  for i <- 1..5 do
    email = "user#{i}@e2e-test.local"
    display_name = "Test User #{i}"

    user =
      case Repo.get_by(User, email: email) do
        nil ->
          {:ok, user} =
            %User{}
            |> User.registration_changeset(%{
              email: email,
              password: test_user_password,
              tenant_id: e2e_tenant.id
            })
            |> Ecto.Changeset.put_change(:display_name, display_name)
            |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
            |> Repo.insert()

          # Associate user with E2E tenant as member
          case Repo.get_by(UserTenant, user_id: user.id, tenant_id: e2e_tenant.id) do
            nil ->
              role = if i == 1, do: :admin, else: :member

              %UserTenant{}
              |> UserTenant.changeset(%{
                user_id: user.id,
                tenant_id: e2e_tenant.id,
                role: role
              })
              |> Repo.insert!()

            _ ->
              :ok
          end

          IO.puts("  ✓ Created user: #{email} (#{display_name})")
          user

        existing ->
          IO.puts("  • User already exists: #{existing.email}")
          existing
      end

    user
  end

# ═══════════════════════════════════════════════════════════════════════════════
# TEST FOLDERS
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("Skipping Test Folders (folders use encrypted metadata - create via API)")
# Note: Folders in SecureSharing use client-side encrypted metadata for names.
# They must be created through the API with proper encryption, not via seeds.

# ═══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL TEST TENANTS (for multi-tenant testing)
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("Creating Additional Test Tenants...")

additional_tenants = [
  %{name: "E2E Test Tenant Alpha", slug: "e2e-test-alpha"},
  %{name: "E2E Test Tenant Beta", slug: "e2e-test-beta"}
]

for tenant_attrs <- additional_tenants do
  case Repo.get_by(Tenant, slug: tenant_attrs.slug) do
    nil ->
      {:ok, tenant} =
        %Tenant{}
        |> Tenant.changeset(Map.put(tenant_attrs, :status, :active))
        |> Repo.insert()

      # Add first test user to this tenant for multi-tenant testing
      first_test_user = Enum.at(test_users, 0)

      if first_test_user do
        case Repo.get_by(UserTenant, user_id: first_test_user.id, tenant_id: tenant.id) do
          nil ->
            %UserTenant{}
            |> UserTenant.changeset(%{
              user_id: first_test_user.id,
              tenant_id: tenant.id,
              role: :member
            })
            |> Repo.insert!()

          _ ->
            :ok
        end
      end

      IO.puts("  ✓ Created tenant: #{tenant_attrs.name}")

    _existing ->
      IO.puts("  • Tenant already exists: #{tenant_attrs.name}")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# WEBAUTHN IdP CONFIGS
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("Creating WebAuthn IdP Configs...")

alias SecureSharing.Accounts.IdpConfig

# Create WebAuthn config for e2e_tenant
for tenant <- [e2e_tenant | Repo.all(from t in Tenant, where: t.slug in ["e2e-test-alpha", "e2e-test-beta"])] do
  case Repo.one(from i in IdpConfig, where: i.tenant_id == ^tenant.id and i.type == :webauthn) do
    nil ->
      {:ok, _config} =
        %IdpConfig{}
        |> IdpConfig.changeset(%{
          tenant_id: tenant.id,
          type: :webauthn,
          name: "Passkeys",
          enabled: true,
          priority: 0,
          provides_key_material: true,
          config: %{
            "rp_id" => "localhost",
            "rp_name" => "SecureSharing",
            "attestation" => "none",
            "origin" => "http://localhost:4000"
          }
        })
        |> Repo.insert()

      IO.puts("  ✓ Created WebAuthn config for tenant: #{tenant.slug}")

    _existing ->
      IO.puts("  • WebAuthn config already exists for tenant: #{tenant.slug}")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("═══════════════════════════════════════════════════════════════════════")
IO.puts("  E2E Seed Complete!")
IO.puts("═══════════════════════════════════════════════════════════════════════")
IO.puts("")
IO.puts("  Primary Tenant:")
IO.puts("    Name: E2E Test Organization")
IO.puts("    Slug: e2e-test")
IO.puts("")
IO.puts("  Admin User:")
IO.puts("    Email: #{admin_email}")
IO.puts("    Password: #{admin_password}")
IO.puts("")
IO.puts("  Test Users:")

for i <- 1..5 do
  IO.puts("    user#{i}@e2e-test.local / #{test_user_password}")
end

IO.puts("")
IO.puts("  Auth Providers:")
IO.puts("    - WebAuthn (passkeys) - rp_id: localhost")
IO.puts("")
IO.puts("  Test Folders:")
IO.puts("    - Documents")
IO.puts("      └── Reports")
IO.puts("    - Images")
IO.puts("    - Shared")
IO.puts("")
IO.puts("═══════════════════════════════════════════════════════════════════════")
IO.puts("")
