defmodule SecureSharing.InvitationsTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Invitations
  alias SecureSharing.Invitations.Invitation
  alias SecureSharing.Accounts

  describe "create_invitation/2" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "creates invitation with valid attributes", %{tenant: tenant, admin: admin} do
      attrs = %{
        email: "newuser@example.com",
        tenant_id: tenant.id,
        role: :member
      }

      assert {:ok, %Invitation{} = invitation} = Invitations.create_invitation(admin, attrs)
      assert invitation.email == "newuser@example.com"
      assert invitation.role == :member
      assert invitation.status == :pending
      assert invitation.tenant_id == tenant.id
      assert invitation.inviter_id == admin.id
      assert invitation.token != nil
      assert invitation.expires_at != nil
    end

    test "creates invitation with custom message", %{tenant: tenant, admin: admin} do
      attrs = %{
        email: "newuser@example.com",
        tenant_id: tenant.id,
        message: "Welcome to our team!"
      }

      assert {:ok, invitation} = Invitations.create_invitation(admin, attrs)
      assert invitation.message == "Welcome to our team!"
    end

    test "creates invitation with admin role", %{tenant: tenant, admin: admin} do
      attrs = %{
        email: "newadmin@example.com",
        tenant_id: tenant.id,
        role: :admin
      }

      assert {:ok, invitation} = Invitations.create_invitation(admin, attrs)
      assert invitation.role == :admin
    end

    test "normalizes email to lowercase", %{tenant: tenant, admin: admin} do
      attrs = %{
        email: "NewUser@Example.COM",
        tenant_id: tenant.id
      }

      assert {:ok, invitation} = Invitations.create_invitation(admin, attrs)
      assert invitation.email == "newuser@example.com"
    end

    test "returns error when email is already registered", %{tenant: tenant, admin: admin} do
      # Create existing user with same email
      insert(:user, email: "existing@example.com", tenant_id: tenant.id)

      attrs = %{
        email: "existing@example.com",
        tenant_id: tenant.id
      }

      assert {:error, :email_already_registered} = Invitations.create_invitation(admin, attrs)
    end

    test "returns error when pending invitation exists for email", %{tenant: tenant, admin: admin} do
      # Create a pending invitation first
      {:ok, _invitation} =
        Invitations.create_invitation(admin, %{
          email: "pending@example.com",
          tenant_id: tenant.id
        })

      # Try to create another invitation for the same email
      attrs = %{
        email: "pending@example.com",
        tenant_id: tenant.id
      }

      assert {:error, :pending_invitation_exists} = Invitations.create_invitation(admin, attrs)
    end

    test "returns error when inviter cannot invite", %{tenant: tenant} do
      # Create a regular member who shouldn't be able to invite
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      attrs = %{
        email: "newuser@example.com",
        tenant_id: tenant.id
      }

      assert {:error, :not_authorized} = Invitations.create_invitation(member, attrs)
    end

    test "returns error when member tries to invite admin", %{tenant: tenant} do
      # Create a regular member who cannot invite
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      attrs = %{
        email: "newadmin@example.com",
        tenant_id: tenant.id,
        role: :admin
      }

      assert {:error, :not_authorized} = Invitations.create_invitation(member, attrs)
    end

    test "platform admin can always invite", %{tenant: tenant} do
      # Platform admin (not just tenant admin)
      platform_admin = insert(:admin_user, tenant_id: tenant.id)

      attrs = %{
        email: "invited@example.com",
        tenant_id: tenant.id,
        role: :admin
      }

      assert {:ok, _invitation} = Invitations.create_invitation(platform_admin, attrs)
    end
  end

  describe "get_invitation_by_token/1" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "returns invitation when token is valid", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "test@example.com",
          tenant_id: tenant.id
        })

      found = Invitations.get_invitation_by_token(invitation.token)
      assert found.id == invitation.id
      assert found.tenant != nil
      assert found.inviter != nil
    end

    test "returns nil for invalid token" do
      assert Invitations.get_invitation_by_token("invalid-token") == nil
    end
  end

  describe "accept_invitation/2" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "accepts invitation and creates user", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: :member
        })

      user_attrs = %{
        password: "secure_password_123",
        display_name: "New User",
        public_keys: %{"ml_kem" => "key1", "ml_dsa" => "key2"},
        encrypted_private_keys: Base.encode64(:crypto.strong_rand_bytes(64)),
        encrypted_master_key: Base.encode64(:crypto.strong_rand_bytes(64)),
        key_derivation_salt: Base.encode64(:crypto.strong_rand_bytes(32))
      }

      assert {:ok, user} = Invitations.accept_invitation(invitation.token, user_attrs)
      assert user.email == "newuser@example.com"
      assert user.display_name == "New User"

      # Verify user is added to tenant with correct role
      user_tenant = Accounts.get_user_tenant(user.id, tenant.id)
      assert user_tenant.role == :member

      # Verify invitation is marked as accepted
      updated_invitation = Invitations.get_invitation(invitation.id)
      assert updated_invitation.status == :accepted
      assert updated_invitation.accepted_by_id == user.id
      assert updated_invitation.accepted_at != nil
    end

    test "returns error for invalid token" do
      assert {:error, :invitation_not_found} =
               Invitations.accept_invitation("invalid-token", %{password: "password123"})
    end

    test "returns error for already accepted invitation", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      user_attrs = %{
        password: "secure_password_123",
        public_keys: %{"ml_kem" => "key1", "ml_dsa" => "key2"},
        encrypted_private_keys: Base.encode64(:crypto.strong_rand_bytes(64)),
        encrypted_master_key: Base.encode64(:crypto.strong_rand_bytes(64)),
        key_derivation_salt: Base.encode64(:crypto.strong_rand_bytes(32))
      }

      # Accept the invitation
      {:ok, _user} = Invitations.accept_invitation(invitation.token, user_attrs)

      # Try to accept again
      assert {:error, :invitation_already_used} =
               Invitations.accept_invitation(invitation.token, user_attrs)
    end

    test "returns error for revoked invitation", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      # Revoke the invitation
      {:ok, _} = Invitations.revoke_invitation(invitation)

      user_attrs = %{password: "secure_password_123"}

      assert {:error, :invitation_revoked} =
               Invitations.accept_invitation(invitation.token, user_attrs)
    end

    test "returns error for expired invitation", %{tenant: tenant, admin: admin} do
      # Create invitation with past expiry
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      user_attrs = %{password: "secure_password_123"}

      assert {:error, :invitation_expired} =
               Invitations.accept_invitation(invitation.token, user_attrs)
    end
  end

  describe "revoke_invitation/1" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "revokes a pending invitation", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      assert {:ok, revoked} = Invitations.revoke_invitation(invitation)
      assert revoked.status == :revoked
    end

    test "returns error when revoking non-pending invitation", %{tenant: tenant, admin: admin} do
      invitation = insert(:accepted_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:error, :cannot_revoke} = Invitations.revoke_invitation(invitation)
    end
  end

  describe "resend_invitation/1" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "resends invitation with new token and expiry", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      original_token = invitation.token
      original_expiry = invitation.expires_at

      # Wait a moment to ensure different timestamp
      :timer.sleep(10)

      assert {:ok, resent} = Invitations.resend_invitation(invitation)
      assert resent.token != original_token
      assert DateTime.compare(resent.expires_at, original_expiry) == :gt
    end

    test "returns error when resending non-pending invitation", %{tenant: tenant, admin: admin} do
      invitation = insert(:revoked_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:error, :cannot_resend} = Invitations.resend_invitation(invitation)
    end
  end

  describe "list_tenant_invitations/2" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "lists all invitations for tenant", %{tenant: tenant, admin: admin} do
      {:ok, _inv1} =
        Invitations.create_invitation(admin, %{email: "user1@example.com", tenant_id: tenant.id})

      {:ok, _inv2} =
        Invitations.create_invitation(admin, %{email: "user2@example.com", tenant_id: tenant.id})

      {:ok, _inv3} =
        Invitations.create_invitation(admin, %{email: "user3@example.com", tenant_id: tenant.id})

      invitations = Invitations.list_tenant_invitations(tenant.id)
      assert length(invitations) == 3
    end

    test "filters by status", %{tenant: tenant, admin: admin} do
      {:ok, inv1} =
        Invitations.create_invitation(admin, %{email: "user1@example.com", tenant_id: tenant.id})

      {:ok, _inv2} =
        Invitations.create_invitation(admin, %{email: "user2@example.com", tenant_id: tenant.id})

      Invitations.revoke_invitation(inv1)

      pending = Invitations.list_tenant_invitations(tenant.id, status: :pending)
      assert length(pending) == 1

      revoked = Invitations.list_tenant_invitations(tenant.id, status: :revoked)
      assert length(revoked) == 1
    end

    test "supports pagination", %{tenant: tenant, admin: admin} do
      for i <- 1..10 do
        Invitations.create_invitation(admin, %{
          email: "user#{i}@example.com",
          tenant_id: tenant.id
        })
      end

      page1 = Invitations.list_tenant_invitations(tenant.id, limit: 3, offset: 0)
      assert length(page1) == 3

      page2 = Invitations.list_tenant_invitations(tenant.id, limit: 3, offset: 3)
      assert length(page2) == 3

      # Make sure they're different
      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "does not include invitations from other tenants", %{tenant: tenant, admin: admin} do
      other_tenant = insert(:tenant)
      other_admin = insert(:admin_user, tenant_id: other_tenant.id)
      insert(:user_tenant, user_id: other_admin.id, tenant_id: other_tenant.id, role: :admin)

      {:ok, _} =
        Invitations.create_invitation(admin, %{email: "user@example.com", tenant_id: tenant.id})

      {:ok, _} =
        Invitations.create_invitation(other_admin, %{
          email: "other@example.com",
          tenant_id: other_tenant.id
        })

      invitations = Invitations.list_tenant_invitations(tenant.id)
      assert length(invitations) == 1
      assert hd(invitations).email == "user@example.com"
    end
  end

  describe "expire_old_invitations/0" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "expires invitations past their expiry date", %{tenant: tenant, admin: admin} do
      # Create an expired invitation (manually set expires_at in the past)
      expired_invitation =
        insert(:invitation,
          tenant_id: tenant.id,
          inviter_id: admin.id,
          expires_at:
            DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:microsecond)
        )

      # Create a valid invitation
      {:ok, valid_invitation} =
        Invitations.create_invitation(admin, %{
          email: "valid@example.com",
          tenant_id: tenant.id
        })

      assert {:ok, count} = Invitations.expire_old_invitations()
      assert count == 1

      # Verify expired invitation is now expired
      updated_expired = Invitations.get_invitation(expired_invitation.id)
      assert updated_expired.status == :expired

      # Verify valid invitation is still pending
      updated_valid = Invitations.get_invitation(valid_invitation.id)
      assert updated_valid.status == :pending
    end

    test "does not expire already processed invitations", %{tenant: tenant, admin: admin} do
      # Create accepted invitation with past expiry
      _accepted =
        insert(:accepted_invitation,
          tenant_id: tenant.id,
          inviter_id: admin.id,
          expires_at:
            DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:microsecond)
        )

      assert {:ok, count} = Invitations.expire_old_invitations()
      assert count == 0
    end
  end

  describe "get_invitation_info/1" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Admin User")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "returns invitation info for valid token", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          message: "Welcome!"
        })

      assert {:ok, info} = Invitations.get_invitation_info(invitation.token)
      assert info.email == "newuser@example.com"
      assert info.role == :member
      assert info.tenant_name == tenant.name
      assert info.inviter_name == "Admin User"
      assert info.message == "Welcome!"
      assert info.valid == true
      assert info.error_reason == nil
    end

    test "returns error for invalid token" do
      assert {:error, :not_found} = Invitations.get_invitation_info("invalid-token")
    end

    test "returns validity info for expired invitation", %{tenant: tenant, admin: admin} do
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:ok, info} = Invitations.get_invitation_info(invitation.token)
      assert info.valid == false
      assert info.error_reason == :expired
    end

    test "returns validity info for revoked invitation", %{tenant: tenant, admin: admin} do
      invitation = insert(:revoked_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:ok, info} = Invitations.get_invitation_info(invitation.token)
      assert info.valid == false
      assert info.error_reason == :revoked
    end

    test "returns validity info for accepted invitation", %{tenant: tenant, admin: admin} do
      invitation = insert(:accepted_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:ok, info} = Invitations.get_invitation_info(invitation.token)
      assert info.valid == false
      assert info.error_reason == :already_used
    end
  end

  describe "can_invite?/2" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "platform admin can always invite", %{tenant: tenant} do
      admin = insert(:admin_user, tenant_id: tenant.id)
      assert Invitations.can_invite?(admin, tenant.id) == true
    end

    test "tenant admin can invite", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :admin)
      assert Invitations.can_invite?(user, tenant.id) == true
    end

    test "tenant owner can invite", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :owner)
      assert Invitations.can_invite?(user, tenant.id) == true
    end

    test "regular member cannot invite", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      assert Invitations.can_invite?(user, tenant.id) == false
    end
  end

  describe "can_invite_role?/2" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "platform admin can invite any role", %{tenant: tenant} do
      admin = insert(:admin_user, tenant_id: tenant.id)
      assert Invitations.can_invite_role?(admin, :admin) == true
      assert Invitations.can_invite_role?(admin, :manager) == true
      assert Invitations.can_invite_role?(admin, :member) == true
    end

    test "admin can invite admin, manager, member", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, role: :admin)
      assert Invitations.can_invite_role?(user, :admin) == true
      assert Invitations.can_invite_role?(user, :manager) == true
      assert Invitations.can_invite_role?(user, :member) == true
    end

    test "owner can invite any role", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, role: :owner)
      assert Invitations.can_invite_role?(user, :admin) == true
      assert Invitations.can_invite_role?(user, :manager) == true
      assert Invitations.can_invite_role?(user, :member) == true
    end

    test "member cannot invite admin or manager", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, role: :member)
      assert Invitations.can_invite_role?(user, :admin) == false
      assert Invitations.can_invite_role?(user, :manager) == false
      assert Invitations.can_invite_role?(user, :member) == true
    end
  end

  describe "count_invitations/2" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "counts all invitations", %{tenant: tenant, admin: admin} do
      {:ok, _} =
        Invitations.create_invitation(admin, %{email: "user1@example.com", tenant_id: tenant.id})

      {:ok, _} =
        Invitations.create_invitation(admin, %{email: "user2@example.com", tenant_id: tenant.id})

      {:ok, inv3} =
        Invitations.create_invitation(admin, %{email: "user3@example.com", tenant_id: tenant.id})

      Invitations.revoke_invitation(inv3)

      assert Invitations.count_invitations(tenant.id) == 3
    end

    test "counts by status", %{tenant: tenant, admin: admin} do
      {:ok, _} =
        Invitations.create_invitation(admin, %{email: "user1@example.com", tenant_id: tenant.id})

      {:ok, _} =
        Invitations.create_invitation(admin, %{email: "user2@example.com", tenant_id: tenant.id})

      {:ok, inv3} =
        Invitations.create_invitation(admin, %{email: "user3@example.com", tenant_id: tenant.id})

      Invitations.revoke_invitation(inv3)

      assert Invitations.count_invitations(tenant.id, :pending) == 2
      assert Invitations.count_invitations(tenant.id, :revoked) == 1
      assert Invitations.count_invitations(tenant.id, :accepted) == 0
    end
  end

  # ============================================================================
  # Token Security Tests (INV-BL-001 to INV-BL-009)
  # ============================================================================

  describe "token generation and security" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "token is 32 bytes (256 bits) of entropy", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      # URL-safe Base64 of 32 bytes = 43 characters (without padding)
      assert String.length(invitation.token) == 43
      # Verify it decodes to 32 bytes
      {:ok, decoded} = Base.url_decode64(invitation.token, padding: false)
      assert byte_size(decoded) == 32
    end

    test "token is URL-safe Base64 encoded", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      # URL-safe Base64 should not contain + or / or =
      refute String.contains?(invitation.token, "+")
      refute String.contains?(invitation.token, "/")
      refute String.contains?(invitation.token, "=")

      # But should be valid URL-safe Base64
      assert {:ok, _decoded} = Base.url_decode64(invitation.token, padding: false)
    end

    test "only hash is stored in database, not plain token", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      original_token = invitation.token

      # Reload from database
      reloaded = Invitations.get_invitation(invitation.id)

      # The virtual field should be nil when loaded from DB
      assert reloaded.token == nil
      # But token_hash should be set
      assert reloaded.token_hash != nil
      # And should match the hash of the original token
      expected_hash = Invitation.hash_token(original_token)
      assert reloaded.token_hash == expected_hash
    end

    test "token hash is SHA-256 (64 character hex string)", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      # Token hash should be 64 characters (256 bits / 4 bits per hex = 64)
      assert String.length(invitation.token_hash) == 64
      # Should be valid lowercase hex
      assert Regex.match?(~r/^[a-f0-9]{64}$/, invitation.token_hash)
    end

    test "same token generates same hash (deterministic)", %{tenant: _tenant, admin: _admin} do
      token = "test_token_12345"
      hash1 = Invitation.hash_token(token)
      hash2 = Invitation.hash_token(token)

      assert hash1 == hash2
    end

    test "different tokens generate different hashes", %{tenant: tenant, admin: admin} do
      {:ok, inv1} =
        Invitations.create_invitation(admin, %{email: "user1@example.com", tenant_id: tenant.id})

      {:ok, inv2} =
        Invitations.create_invitation(admin, %{email: "user2@example.com", tenant_id: tenant.id})

      assert inv1.token != inv2.token
      assert inv1.token_hash != inv2.token_hash
    end

    test "tokens are cryptographically random (no duplicates in batch)", %{
      tenant: tenant,
      admin: admin
    } do
      # Generate unique emails using timestamp to avoid conflicts
      unique_id = System.unique_integer([:positive])

      tokens =
        for i <- 1..50 do
          {:ok, inv} =
            Invitations.create_invitation(admin, %{
              email: "batch_#{unique_id}_user#{i}@example.com",
              tenant_id: tenant.id
            })

          inv.token
        end

      # All tokens should be unique
      assert length(Enum.uniq(tokens)) == 50
    end
  end

  # ============================================================================
  # Email Handling Tests
  # ============================================================================

  describe "email handling" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "trims whitespace from email", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "  spaces@example.com  ",
          tenant_id: tenant.id
        })

      assert invitation.email == "spaces@example.com"
    end

    test "normalizes mixed case email", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "MixedCase@EXAMPLE.COM",
          tenant_id: tenant.id
        })

      assert invitation.email == "mixedcase@example.com"
    end

    test "handles email with + addressing", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "user+tag@example.com",
          tenant_id: tenant.id
        })

      assert invitation.email == "user+tag@example.com"
    end

    test "handles email with subdomain", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "user@mail.example.co.uk",
          tenant_id: tenant.id
        })

      assert invitation.email == "user@mail.example.co.uk"
    end
  end

  # ============================================================================
  # Default Values Tests
  # ============================================================================

  describe "default values" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "defaults role to member when not specified", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
          # No role specified
        })

      assert invitation.role == :member
    end

    test "defaults status to pending", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      assert invitation.status == :pending
    end

    test "sets expiration to 7 days by default", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      now = DateTime.utc_now()
      # Should be approximately 7 days (168 hours) in the future
      diff_seconds = DateTime.diff(invitation.expires_at, now)
      # Allow 60 seconds of variance for test execution time
      expected_seconds = 7 * 24 * 60 * 60
      assert abs(diff_seconds - expected_seconds) < 60
    end
  end

  # ============================================================================
  # Role Hierarchy Tests
  # Note: The system only supports member, admin, owner roles (no manager role)
  # ============================================================================

  describe "role hierarchy tests" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "member cannot invite anyone", %{tenant: tenant} do
      # Create a regular user with member role
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      result =
        Invitations.create_invitation(member, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: :member
        })

      assert {:error, :not_authorized} = result
    end

    test "member cannot invite admin", %{tenant: tenant} do
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      result =
        Invitations.create_invitation(member, %{
          email: "admin@example.com",
          tenant_id: tenant.id,
          role: :admin
        })

      assert {:error, :not_authorized} = result
    end

    test "admin can invite member", %{tenant: tenant} do
      # Use admin_user factory which sets is_admin: true
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)

      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "member@example.com",
          tenant_id: tenant.id,
          role: :member
        })

      assert invitation.role == :member
    end

    test "admin can invite admin", %{tenant: tenant} do
      # Use admin_user factory which sets is_admin: true
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)

      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newadmin@example.com",
          tenant_id: tenant.id,
          role: :admin
        })

      assert invitation.role == :admin
    end
  end

  # ============================================================================
  # State Transition Tests (INV-EDGE-015 to INV-EDGE-020)
  # ============================================================================

  describe "state transitions" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "pending → accepted is valid", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      user_attrs = %{
        password: "secure_password_123",
        display_name: "New User",
        public_keys: %{"ml_kem" => "key1", "ml_dsa" => "key2"},
        encrypted_private_keys: Base.encode64(:crypto.strong_rand_bytes(64)),
        encrypted_master_key: Base.encode64(:crypto.strong_rand_bytes(64)),
        key_derivation_salt: Base.encode64(:crypto.strong_rand_bytes(32))
      }

      assert {:ok, _user} = Invitations.accept_invitation(invitation.token, user_attrs)

      updated = Invitations.get_invitation(invitation.id)
      assert updated.status == :accepted
    end

    test "pending → revoked is valid", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      assert {:ok, revoked} = Invitations.revoke_invitation(invitation)
      assert revoked.status == :revoked
    end

    test "accepted invitation cannot transition to any other state", %{
      tenant: tenant,
      admin: admin
    } do
      invitation = insert(:accepted_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      # Cannot revoke
      assert {:error, :cannot_revoke} = Invitations.revoke_invitation(invitation)

      # Cannot resend
      assert {:error, :cannot_resend} = Invitations.resend_invitation(invitation)
    end

    test "revoked invitation cannot be resent", %{tenant: tenant, admin: admin} do
      invitation = insert(:revoked_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:error, :cannot_resend} = Invitations.resend_invitation(invitation)
    end

    test "expired invitation cannot be revoked or resent", %{tenant: tenant, admin: admin} do
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      assert {:error, :cannot_revoke} = Invitations.revoke_invitation(invitation)
      assert {:error, :cannot_resend} = Invitations.resend_invitation(invitation)
    end
  end

  # ============================================================================
  # Boundary Condition Tests (INV-EDGE-001 to INV-EDGE-008)
  # ============================================================================

  describe "boundary conditions" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "invitation expiring exactly now is treated as expired", %{tenant: tenant, admin: admin} do
      # Create invitation that expires exactly now
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      invitation =
        insert(:invitation,
          tenant_id: tenant.id,
          inviter_id: admin.id,
          expires_at: now,
          status: :pending
        )

      # Brief pause to ensure we're past the expiry
      :timer.sleep(10)

      assert Invitation.valid?(invitation) == false
    end

    test "invitation expiring in 1 second is still valid", %{tenant: tenant, admin: admin} do
      # Create invitation that expires in 1 second
      future = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.truncate(:microsecond)

      invitation =
        insert(:invitation,
          tenant_id: tenant.id,
          inviter_id: admin.id,
          expires_at: future,
          status: :pending
        )

      assert Invitation.valid?(invitation) == true
    end

    test "email at exactly 255 characters is valid", %{tenant: tenant, admin: admin} do
      # Create a 255 character email
      # local@domain.tld format: local_part + @ + domain = 255
      # Using: local_part + "@e.com" (6 chars) = 255
      # So local_part needs to be 249 chars
      local_part = String.duplicate("a", 249)
      domain = "e.com"
      email = "#{local_part}@#{domain}"
      assert String.length(email) == 255

      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: email,
          tenant_id: tenant.id
        })

      assert invitation.email == email
    end

    test "empty invitation list returns empty array", %{tenant: tenant, admin: _admin} do
      invitations = Invitations.list_tenant_invitations(tenant.id)
      assert invitations == []
    end

    test "count returns 0 for empty tenant", %{tenant: tenant, admin: _admin} do
      assert Invitations.count_invitations(tenant.id) == 0
      assert Invitations.count_invitations(tenant.id, :pending) == 0
    end
  end

  # ============================================================================
  # Null/Empty Handling Tests (INV-EDGE-021 to INV-EDGE-023)
  # ============================================================================

  describe "null and empty handling" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "null message stored correctly", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          message: nil
        })

      assert invitation.message == nil

      # Verify persisted correctly
      reloaded = Invitations.get_invitation(invitation.id)
      assert reloaded.message == nil
    end

    test "empty string message stored correctly", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          message: ""
        })

      # Empty string should be stored as empty (or nil depending on implementation)
      assert invitation.message == "" or invitation.message == nil
    end

    test "invitation info handles null inviter display_name", %{tenant: tenant, admin: admin} do
      # Create admin without display_name
      admin_without_name = insert(:admin_user, tenant_id: tenant.id, display_name: nil)
      insert(:user_tenant, user_id: admin_without_name.id, tenant_id: tenant.id, role: :admin)

      {:ok, invitation} =
        Invitations.create_invitation(admin_without_name, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      {:ok, info} = Invitations.get_invitation_info(invitation.token)

      # Should fall back to email when display_name is nil
      assert info.inviter_name == admin_without_name.email
    end
  end

  # ============================================================================
  # Role String/Atom Handling Tests
  # ============================================================================

  describe "role normalization" do
    setup do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "accepts role as string", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: "admin"
        })

      assert invitation.role == :admin
    end

    test "accepts role as atom", %{tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: :manager
        })

      assert invitation.role == :manager
    end
  end

  # ============================================================================
  # Invitation Validity Check Tests
  # ============================================================================

  describe "Invitation.valid?/1" do
    test "returns true for pending invitation with future expiry" do
      invitation = %Invitation{
        status: :pending,
        expires_at:
          DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:microsecond)
      }

      assert Invitation.valid?(invitation) == true
    end

    test "returns false for pending invitation with past expiry" do
      invitation = %Invitation{
        status: :pending,
        expires_at:
          DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:microsecond)
      }

      assert Invitation.valid?(invitation) == false
    end

    test "returns false for accepted invitation" do
      invitation = %Invitation{
        status: :accepted,
        expires_at:
          DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:microsecond)
      }

      assert Invitation.valid?(invitation) == false
    end

    test "returns false for revoked invitation" do
      invitation = %Invitation{
        status: :revoked,
        expires_at:
          DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:microsecond)
      }

      assert Invitation.valid?(invitation) == false
    end

    test "returns false for expired invitation" do
      invitation = %Invitation{
        status: :expired,
        expires_at:
          DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:microsecond)
      }

      assert Invitation.valid?(invitation) == false
    end
  end
end
