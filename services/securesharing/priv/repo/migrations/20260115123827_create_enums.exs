defmodule SecureSharing.Repo.Migrations.CreateEnums do
  use Ecto.Migration

  def change do
    # User status
    execute(
      "CREATE TYPE user_status AS ENUM ('active', 'suspended', 'pending_recovery')",
      "DROP TYPE user_status"
    )

    # Credential types
    execute(
      "CREATE TYPE credential_type AS ENUM ('password', 'webauthn', 'oidc', 'digital_id')",
      "DROP TYPE credential_type"
    )

    # Permission levels
    execute(
      "CREATE TYPE permission_level AS ENUM ('read', 'write', 'admin', 'owner')",
      "DROP TYPE permission_level"
    )

    # Resource types for sharing
    execute(
      "CREATE TYPE resource_type AS ENUM ('file', 'folder')",
      "DROP TYPE resource_type"
    )

    # Recovery request status
    execute(
      "CREATE TYPE recovery_status AS ENUM ('pending', 'approved', 'completed', 'expired', 'cancelled')",
      "DROP TYPE recovery_status"
    )

    # Audit event types
    execute(
      "CREATE TYPE audit_event_type AS ENUM (
        'user_registered', 'user_login', 'user_logout',
        'file_created', 'file_downloaded', 'file_deleted',
        'folder_created', 'folder_deleted',
        'share_created', 'share_revoked', 'share_accessed',
        'recovery_initiated', 'recovery_approved', 'recovery_completed'
      )",
      "DROP TYPE audit_event_type"
    )
  end
end
