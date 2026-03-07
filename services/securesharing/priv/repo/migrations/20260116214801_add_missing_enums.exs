defmodule SecureSharing.Repo.Migrations.AddMissingEnums do
  @moduledoc """
  Adds missing enum types to match 02-database-schema.md.

  These enums support:
  - Tenant lifecycle (status, plan)
  - User roles within tenants
  - Identity provider types
  - Recovery request reasons
  """
  use Ecto.Migration

  def change do
    # Tenant status
    execute(
      "CREATE TYPE tenant_status AS ENUM ('active', 'suspended', 'deleted')",
      "DROP TYPE tenant_status"
    )

    # Tenant plan
    execute(
      "CREATE TYPE tenant_plan AS ENUM ('free', 'pro', 'enterprise')",
      "DROP TYPE tenant_plan"
    )

    # User role within tenant
    execute(
      "CREATE TYPE user_role AS ENUM ('member', 'admin', 'owner')",
      "DROP TYPE user_role"
    )

    # Identity provider type
    execute(
      "CREATE TYPE idp_type AS ENUM ('webauthn', 'digital_id', 'oidc', 'saml')",
      "DROP TYPE idp_type"
    )

    # Recovery reason
    execute(
      "CREATE TYPE recovery_reason AS ENUM ('device_lost', 'passkey_unavailable', 'credential_reset', 'admin_request')",
      "DROP TYPE recovery_reason"
    )

    # Add 'saml' to existing credential_type enum
    execute(
      "ALTER TYPE credential_type ADD VALUE IF NOT EXISTS 'saml'",
      "SELECT 1"
    )
  end
end
