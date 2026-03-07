defmodule SecureSharing.Factory do
  @moduledoc """
  Test factories for generating test data.
  """
  use ExMachina.Ecto, repo: SecureSharing.Repo

  alias SecureSharing.Accounts.{Credential, IdpConfig, Tenant, User, UserTenant}
  alias SecureSharing.Devices.{Device, DeviceEnrollment}
  alias SecureSharing.Files.{Folder, File}
  alias SecureSharing.Sharing.{AccessRequest, ShareGrant}
  alias SecureSharing.Recovery.{RecoveryConfig, RecoveryShare, RecoveryRequest, RecoveryApproval}
  alias SecureSharing.Invitations.Invitation

  def tenant_factory do
    %Tenant{
      name: sequence(:tenant_name, &"Test Tenant #{&1}"),
      slug: sequence(:tenant_slug, &"test-tenant-#{&1}"),
      storage_quota_bytes: 10_737_418_240,
      max_users: 100,
      settings: %{}
    }
  end

  def user_factory do
    # Note: tenant_id must be provided when inserting
    # Use: insert(:user, tenant_id: tenant.id) or insert(:user, tenant: tenant)
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      status: :active,
      hashed_password: Bcrypt.hash_pwd_salt("valid_password123"),
      public_keys: %{
        "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
      },
      encrypted_private_keys: :crypto.strong_rand_bytes(64),
      encrypted_master_key: :crypto.strong_rand_bytes(64),
      key_derivation_salt: :crypto.strong_rand_bytes(32),
      recovery_setup_complete: false,
      is_admin: false
    }
  end

  @doc """
  Create an admin user for testing admin functionality.
  """
  def admin_user_factory do
    struct!(
      user_factory(),
      %{
        is_admin: true
      }
    )
  end

  @doc """
  Create a user-tenant association for multi-tenant support.
  Note: user_id and tenant_id must be provided when inserting.
  """
  def user_tenant_factory do
    %UserTenant{
      role: :member,
      status: "active",
      joined_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  @doc """
  Create a user with a specific password for testing authentication.
  """
  def user_with_password_factory do
    struct!(
      user_factory(),
      %{
        hashed_password: Bcrypt.hash_pwd_salt("test_password_123")
      }
    )
  end

  # ============================================================================
  # Device Factories
  # ============================================================================

  @doc """
  Create a device.
  """
  def device_factory do
    %Device{
      device_fingerprint: sequence(:fingerprint, &"device-fingerprint-#{&1}"),
      platform: :android,
      device_info: %{
        "manufacturer" => "Samsung",
        "model" => "Galaxy S24",
        "os_version" => "14"
      },
      status: :active,
      trust_level: :medium
    }
  end

  @doc """
  Create a device enrollment.
  Note: device_id, user_id, and tenant_id must be provided when inserting.
  """
  def device_enrollment_factory do
    %DeviceEnrollment{
      device_public_key: :crypto.strong_rand_bytes(1312),
      key_algorithm: :kaz_sign,
      device_name: sequence(:device_name, &"My Device #{&1}"),
      status: :active,
      enrolled_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  @doc """
  Create a root folder for a user.
  Note: tenant_id and owner_id must be provided when inserting.
  """
  def folder_factory do
    %Folder{
      encrypted_metadata: :crypto.strong_rand_bytes(64),
      metadata_nonce: :crypto.strong_rand_bytes(12),
      wrapped_kek: :crypto.strong_rand_bytes(64),
      kem_ciphertext: :crypto.strong_rand_bytes(128),
      owner_wrapped_kek: :crypto.strong_rand_bytes(64),
      owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
      signature: :crypto.strong_rand_bytes(256),
      is_root: false
    }
  end

  def root_folder_factory do
    struct!(
      folder_factory(),
      %{
        is_root: true,
        parent_id: nil
      }
    )
  end

  @doc """
  Create a file in a folder.
  Note: tenant_id, owner_id, and folder_id must be provided when inserting.
  """
  def file_factory do
    %File{
      encrypted_metadata: :crypto.strong_rand_bytes(128),
      wrapped_dek: :crypto.strong_rand_bytes(64),
      kem_ciphertext: :crypto.strong_rand_bytes(128),
      signature: :crypto.strong_rand_bytes(256),
      blob_size: :rand.uniform(1_000_000),
      blob_hash: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
      storage_path: sequence(:storage_path, &"uploads/#{&1}/#{UUIDv7.generate()}"),
      chunk_count: 1,
      status: "complete"
    }
  end

  @doc """
  Create a share grant.
  Note: tenant_id, grantor_id, grantee_id, resource_type, and resource_id must be provided.
  """
  def share_grant_factory do
    %ShareGrant{
      wrapped_key: :crypto.strong_rand_bytes(64),
      kem_ciphertext: :crypto.strong_rand_bytes(128),
      algorithm: "kaz",
      permission: :read,
      recursive: true,
      signature: :crypto.strong_rand_bytes(256)
    }
  end

  def file_share_factory do
    struct!(
      share_grant_factory(),
      %{
        resource_type: :file,
        recursive: false
      }
    )
  end

  def folder_share_factory do
    struct!(
      share_grant_factory(),
      %{
        resource_type: :folder,
        recursive: true
      }
    )
  end

  # ============================================================================
  # Access Request Factories
  # ============================================================================

  @doc """
  Create an access request (permission upgrade request).
  Note: tenant_id, share_grant_id, and requester_id must be provided.
  """
  def access_request_factory do
    %AccessRequest{
      requested_permission: :write,
      status: :pending,
      reason: "I need edit access to update the document"
    }
  end

  # ============================================================================
  # Recovery Factories
  # ============================================================================

  @doc """
  Create a recovery configuration.
  Note: user_id must be provided.
  """
  def recovery_config_factory do
    %RecoveryConfig{
      threshold: 3,
      total_shares: 5,
      setup_complete: false
    }
  end

  @doc """
  Create a recovery share.
  Note: config_id, owner_id, and trustee_id must be provided.
  """
  def recovery_share_factory do
    %RecoveryShare{
      share_index: sequence(:share_index, & &1),
      encrypted_share: :crypto.strong_rand_bytes(64),
      kem_ciphertext: :crypto.strong_rand_bytes(128),
      signature: :crypto.strong_rand_bytes(256),
      accepted: false
    }
  end

  @doc """
  Create a recovery request.
  Note: config_id and user_id must be provided.
  """
  def recovery_request_factory do
    %RecoveryRequest{
      new_public_key: :crypto.strong_rand_bytes(128),
      reason: "Lost device",
      status: :pending,
      expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:microsecond)
    }
  end

  @doc """
  Create a recovery approval.
  Note: request_id, share_id, and trustee_id must be provided.
  """
  def recovery_approval_factory do
    %RecoveryApproval{
      reencrypted_share: :crypto.strong_rand_bytes(64),
      kem_ciphertext: :crypto.strong_rand_bytes(128),
      signature: :crypto.strong_rand_bytes(256)
    }
  end

  # ============================================================================
  # Invitation Factories
  # ============================================================================

  @doc """
  Create an invitation.
  Note: tenant_id and inviter_id must be provided when inserting.
  """
  def invitation_factory do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    %Invitation{
      email: sequence(:invitation_email, &"invitee#{&1}@example.com"),
      # Use same hash format as Invitation.hash_token/1
      token_hash: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower),
      role: :member,
      status: :pending,
      expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:microsecond),
      metadata: %{}
    }
    |> Map.put(:token, token)
  end

  @doc """
  Create an accepted invitation.
  """
  def accepted_invitation_factory do
    struct!(
      invitation_factory(),
      %{
        status: :accepted,
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      }
    )
  end

  @doc """
  Create an expired invitation.
  """
  def expired_invitation_factory do
    struct!(
      invitation_factory(),
      %{
        status: :expired,
        expires_at:
          DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:microsecond)
      }
    )
  end

  @doc """
  Create a revoked invitation.
  """
  def revoked_invitation_factory do
    struct!(
      invitation_factory(),
      %{
        status: :revoked
      }
    )
  end

  # ============================================================================
  # IdP Config Factories
  # ============================================================================

  @doc """
  Create a WebAuthn IdP configuration.
  Note: tenant_id must be provided when inserting.
  """
  def idp_config_factory do
    %IdpConfig{
      type: :webauthn,
      name: "Passkeys",
      enabled: true,
      priority: 0,
      provides_key_material: true,
      config: %{
        "rp_id" => "localhost",
        "rp_name" => "SecureSharing Test",
        "attestation" => "none"
      }
    }
  end

  @doc """
  Create an OIDC IdP configuration.
  Note: tenant_id must be provided when inserting.
  """
  def oidc_idp_config_factory do
    %IdpConfig{
      type: :oidc,
      name: sequence(:oidc_name, &"OIDC Provider #{&1}"),
      enabled: true,
      priority: 10,
      provides_key_material: false,
      config: %{
        "issuer" => "https://accounts.google.com",
        "client_id" => sequence(:client_id, &"client-#{&1}.apps.googleusercontent.com"),
        "client_secret" => "test-secret",
        "redirect_uri" => "http://localhost:4000/auth/oidc/callback",
        "scope" => "openid email profile"
      }
    }
  end

  # ============================================================================
  # Credential Factories
  # ============================================================================

  @doc """
  Create a WebAuthn credential.
  Note: user_id must be provided. provider_id is optional.
  """
  def webauthn_credential_factory do
    %Credential{
      type: :webauthn,
      credential_id: :crypto.strong_rand_bytes(64),
      public_key: :crypto.strong_rand_bytes(77),
      counter: 0,
      transports: %{"transports" => ["internal"]},
      encrypted_master_key: :crypto.strong_rand_bytes(64),
      mk_nonce: :crypto.strong_rand_bytes(12),
      device_name: sequence(:cred_device_name, &"Passkey #{&1}")
    }
  end

  @doc """
  Create an OIDC credential.
  Note: user_id and provider_id must be provided.
  """
  def oidc_credential_factory do
    %Credential{
      type: :oidc,
      external_id: sequence(:external_id, &"oidc-sub-#{&1}"),
      device_name: sequence(:oidc_device_name, &"OIDC Login #{&1}")
    }
  end
end
