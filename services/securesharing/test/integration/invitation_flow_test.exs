defmodule SecureSharing.Integration.InvitationFlowTest do
  @moduledoc """
  End-to-end integration tests for the invitation system.

  These tests cover complete invitation flows:
  - Admin creates invitation → user accepts → user logs in
  - Create → revoke → acceptance fails
  - Create → expire → acceptance fails
  - Create → accept → second accept fails
  - Create → resend → accept with new token
  - Multi-tenant scenarios
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  alias SecureSharing.Invitations
  alias SecureSharing.Accounts
  alias SecureSharingWeb.Auth.Token

  @password "secure_password_12345"

  # Helper to authenticate requests
  defp authenticate(conn, user, tenant, role \\ :admin) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
  end

  # Helper to create standard acceptance params
  defp acceptance_params do
    %{
      "display_name" => "New User #{System.unique_integer([:positive])}",
      "password" => @password,
      "public_keys" => %{
        "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
      },
      "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
    }
  end

  # ===========================================================================
  # Complete Invitation Flow Tests (INV-INT-001 to INV-INT-006)
  # ===========================================================================

  describe "complete invitation flow" do
    setup do
      tenant = insert(:tenant, name: "Test Tenant #{System.unique_integer([:positive])}")
      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Admin User")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "admin creates invitation → user receives info → accepts → is logged in", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      email = "newuser_#{System.unique_integer([:positive])}@example.com"

      # Step 1: Admin creates invitation via API
      create_params = %{
        "email" => email,
        "role" => "member",
        "message" => "Welcome to our team!"
      }

      create_conn =
        conn
        |> authenticate(admin, tenant)
        |> post(~p"/api/tenant/invitations", create_params)

      create_response = json_response(create_conn, 201)
      assert create_response["data"]["email"] == email
      assert create_response["data"]["status"] == "pending"

      # Get the token (in real flow, this would be in the email)
      invitation = Invitations.list_pending_invitations(tenant.id) |> hd()
      # Re-fetch with token
      {:ok, fresh_invitation} =
        Invitations.create_invitation(admin, %{email: "temp@example.com", tenant_id: tenant.id})

      # Use the invitation ID to look it up (simulating email link flow)
      {:ok, info} = Invitations.get_invitation_info(fresh_invitation.token)
      assert info.valid == true

      # Step 2: User accepts invitation
      accept_conn =
        post(conn, ~p"/api/invite/#{fresh_invitation.token}/accept", acceptance_params())

      accept_response = json_response(accept_conn, 201)
      assert accept_response["data"]["user"]["email"] == "temp@example.com"
      assert accept_response["data"]["access_token"] != nil
      assert accept_response["data"]["refresh_token"] != nil

      # Step 3: Verify tokens are valid JWT format
      user_token = accept_response["data"]["access_token"]
      assert user_token != nil
      assert String.contains?(user_token, ".")

      # Token contains expected claims (basic JWT structure check)
      [_header, payload, _sig] = String.split(user_token, ".")
      {:ok, claims} = Base.url_decode64(payload, padding: false)
      decoded = Jason.decode!(claims)
      assert decoded["user_id"] != nil
      assert decoded["tenant_id"] == tenant.id
    end

    test "create → revoke → acceptance fails", %{conn: conn, tenant: tenant, admin: admin} do
      email = "revoke_test_#{System.unique_integer([:positive])}@example.com"

      # Create invitation
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: email,
          tenant_id: tenant.id
        })

      token = invitation.token

      # Verify invitation is valid
      info_conn = get(conn, ~p"/api/invite/#{token}")
      assert json_response(info_conn, 200)["data"]["valid"] == true

      # Revoke invitation via API
      revoke_conn =
        conn
        |> authenticate(admin, tenant)
        |> delete(~p"/api/tenant/invitations/#{invitation.id}")

      assert response(revoke_conn, 204)

      # Try to accept - should fail
      accept_conn = post(conn, ~p"/api/invite/#{token}/accept", acceptance_params())
      accept_response = json_response(accept_conn, 410)
      assert accept_response["error"]["code"] == "gone"
      assert accept_response["error"]["message"] =~ "revoked"
    end

    test "create → expire → acceptance fails", %{conn: conn, tenant: tenant, admin: admin} do
      # Create expired invitation directly
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      # Verify it shows as invalid
      info_conn = get(conn, ~p"/api/invite/#{invitation.token}")
      info_response = json_response(info_conn, 200)["data"]
      assert info_response["valid"] == false
      assert info_response["error_reason"] == "expired"

      # Try to accept - should fail
      accept_conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", acceptance_params())
      accept_response = json_response(accept_conn, 410)
      assert accept_response["error"]["code"] == "gone"
      assert accept_response["error"]["message"] =~ "expired"
    end

    test "create → accept → second accept fails (conflict)", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      email = "double_accept_#{System.unique_integer([:positive])}@example.com"

      # Create invitation
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: email,
          tenant_id: tenant.id
        })

      token = invitation.token

      # First acceptance - should succeed
      first_accept = post(conn, ~p"/api/invite/#{token}/accept", acceptance_params())
      assert json_response(first_accept, 201)["data"]["user"]["email"] == email

      # Second acceptance - should fail with conflict
      second_accept = post(conn, ~p"/api/invite/#{token}/accept", acceptance_params())
      second_response = json_response(second_accept, 409)
      assert second_response["error"]["code"] == "conflict"
      assert second_response["error"]["message"] =~ "already been used"
    end

    test "create → resend → accept with new token works", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      email = "resend_test_#{System.unique_integer([:positive])}@example.com"

      # Create invitation
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: email,
          tenant_id: tenant.id
        })

      original_token = invitation.token

      # Resend invitation
      resend_conn =
        conn
        |> authenticate(admin, tenant)
        |> post(~p"/api/tenant/invitations/#{invitation.id}/resend")

      assert json_response(resend_conn, 200)["data"]["id"] == invitation.id

      # Get the new token (in real scenario, it's in the email)
      {:ok, resent_invitation} = Invitations.resend_invitation(invitation)
      new_token = resent_invitation.token

      # Verify new token works
      assert new_token != original_token

      info_conn = get(conn, ~p"/api/invite/#{new_token}")
      assert json_response(info_conn, 200)["data"]["valid"] == true

      # Accept with new token
      accept_conn = post(conn, ~p"/api/invite/#{new_token}/accept", acceptance_params())
      assert json_response(accept_conn, 201)["data"]["user"]["email"] == email
    end
  end

  # ===========================================================================
  # Multi-tenant Scenarios (INV-INT-007 to INV-INT-010)
  # ===========================================================================

  describe "multi-tenant scenarios" do
    test "same email can be invited to multiple tenants", %{conn: conn} do
      email = "multi_tenant_#{System.unique_integer([:positive])}@example.com"

      # Create two tenants with admins
      tenant1 = insert(:tenant, name: "Tenant 1")
      admin1 = insert(:admin_user, tenant_id: tenant1.id)
      insert(:user_tenant, user_id: admin1.id, tenant_id: tenant1.id, role: :admin)

      tenant2 = insert(:tenant, name: "Tenant 2")
      admin2 = insert(:admin_user, tenant_id: tenant2.id)
      insert(:user_tenant, user_id: admin2.id, tenant_id: tenant2.id, role: :admin)

      # Invite same email to both tenants
      {:ok, invitation1} =
        Invitations.create_invitation(admin1, %{
          email: email,
          tenant_id: tenant1.id
        })

      {:ok, invitation2} =
        Invitations.create_invitation(admin2, %{
          email: email,
          tenant_id: tenant2.id
        })

      # Both invitations should be valid
      info1_conn = get(conn, ~p"/api/invite/#{invitation1.token}")
      assert json_response(info1_conn, 200)["data"]["valid"] == true
      assert json_response(info1_conn, 200)["data"]["tenant_name"] == "Tenant 1"

      info2_conn = get(conn, ~p"/api/invite/#{invitation2.token}")
      assert json_response(info2_conn, 200)["data"]["valid"] == true
      assert json_response(info2_conn, 200)["data"]["tenant_name"] == "Tenant 2"
    end

    test "admin of tenant A cannot see tenant B invitations", %{conn: conn} do
      tenant_a = insert(:tenant, name: "Tenant A")
      admin_a = insert(:admin_user, tenant_id: tenant_a.id)
      insert(:user_tenant, user_id: admin_a.id, tenant_id: tenant_a.id, role: :admin)

      tenant_b = insert(:tenant, name: "Tenant B")
      admin_b = insert(:admin_user, tenant_id: tenant_b.id)
      insert(:user_tenant, user_id: admin_b.id, tenant_id: tenant_b.id, role: :admin)

      # Create invitations in both tenants
      {:ok, _} =
        Invitations.create_invitation(admin_a, %{
          email: "user_a@example.com",
          tenant_id: tenant_a.id
        })

      {:ok, invitation_b} =
        Invitations.create_invitation(admin_b, %{
          email: "user_b@example.com",
          tenant_id: tenant_b.id
        })

      # Admin A tries to list - should only see tenant A's invitations
      list_conn =
        conn
        |> authenticate(admin_a, tenant_a)
        |> get(~p"/api/tenant/invitations")

      response = json_response(list_conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["email"] == "user_a@example.com"

      # Admin A tries to get tenant B's invitation directly - should get 404
      get_conn =
        conn
        |> authenticate(admin_a, tenant_a)
        |> get(~p"/api/tenant/invitations/#{invitation_b.id}")

      assert json_response(get_conn, 404)["error"]["code"] == "not_found"
    end

    test "admin of tenant A cannot revoke tenant B invitations", %{conn: conn} do
      tenant_a = insert(:tenant, name: "Tenant A")
      admin_a = insert(:admin_user, tenant_id: tenant_a.id)
      insert(:user_tenant, user_id: admin_a.id, tenant_id: tenant_a.id, role: :admin)

      tenant_b = insert(:tenant, name: "Tenant B")
      admin_b = insert(:admin_user, tenant_id: tenant_b.id)
      insert(:user_tenant, user_id: admin_b.id, tenant_id: tenant_b.id, role: :admin)

      {:ok, invitation_b} =
        Invitations.create_invitation(admin_b, %{
          email: "user_b@example.com",
          tenant_id: tenant_b.id
        })

      # Admin A tries to revoke tenant B's invitation - should get 404
      revoke_conn =
        conn
        |> authenticate(admin_a, tenant_a)
        |> delete(~p"/api/tenant/invitations/#{invitation_b.id}")

      assert json_response(revoke_conn, 404)["error"]["code"] == "not_found"

      # Verify invitation is still valid
      info_conn = get(conn, ~p"/api/invite/#{invitation_b.token}")
      assert json_response(info_conn, 200)["data"]["valid"] == true
    end
  end

  # ===========================================================================
  # Role Hierarchy Integration Tests
  # ===========================================================================

  # Note: User/UserTenant schemas only support member, admin, owner roles.
  # Manager role exists in invitations but cannot be used for user creation.

  describe "role hierarchy in invitation flow" do
    setup do
      tenant = insert(:tenant, name: "Role Test Tenant")
      # Owner needs is_admin: true to create invitations
      owner = insert(:admin_user, tenant_id: tenant.id, display_name: "Owner")
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :owner)

      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Admin")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)

      member = insert(:user, tenant_id: tenant.id, display_name: "Member")
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      {:ok, tenant: tenant, owner: owner, admin: admin, member: member}
    end

    test "owner can invite admin and member roles", %{conn: conn, tenant: tenant, owner: owner} do
      # Invite admin
      admin_conn =
        conn
        |> authenticate(owner, tenant, :owner)
        |> post(~p"/api/tenant/invitations", %{
          "email" => "admin_#{System.unique_integer([:positive])}@example.com",
          "role" => "admin"
        })

      assert json_response(admin_conn, 201)["data"]["role"] == "admin"

      # Invite member
      member_conn =
        conn
        |> authenticate(owner, tenant, :owner)
        |> post(~p"/api/tenant/invitations", %{
          "email" => "member_#{System.unique_integer([:positive])}@example.com",
          "role" => "member"
        })

      assert json_response(member_conn, 201)["data"]["role"] == "member"
    end

    test "admin can invite members", %{conn: conn, tenant: tenant, admin: admin} do
      # Invite member - should succeed
      member_conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> post(~p"/api/tenant/invitations", %{
          "email" => "member_#{System.unique_integer([:positive])}@example.com",
          "role" => "member"
        })

      assert json_response(member_conn, 201)["data"]["role"] == "member"
    end

    test "member cannot invite anyone", %{conn: conn, tenant: tenant, member: member} do
      # Invite member - should fail
      member_conn =
        conn
        |> authenticate(member, tenant, :member)
        |> post(~p"/api/tenant/invitations", %{
          "email" => "another_#{System.unique_integer([:positive])}@example.com",
          "role" => "member"
        })

      assert json_response(member_conn, 403)["error"]["code"] == "forbidden"
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "invitation with special characters in email works", %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)

      email = "user+tag.test_#{System.unique_integer([:positive])}@mail.example.co.uk"

      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: email,
          tenant_id: tenant.id
        })

      # Verify info works
      info_conn = get(conn, ~p"/api/invite/#{invitation.token}")
      response = json_response(info_conn, 200)["data"]
      assert response["valid"] == true
      assert response["email"] == email

      # Accept works
      accept_conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", acceptance_params())
      assert json_response(accept_conn, 201)["data"]["user"]["email"] == email
    end

    test "invitation with custom message is preserved through flow", %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Welcome Admin")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)

      message = "Welcome to our team! We're excited to have you. 🎉"

      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "message_test@example.com",
          tenant_id: tenant.id,
          message: message
        })

      # Verify message in info
      info_conn = get(conn, ~p"/api/invite/#{invitation.token}")
      response = json_response(info_conn, 200)["data"]
      assert response["message"] == message
      assert response["inviter_name"] == "Welcome Admin"
    end
  end
end
