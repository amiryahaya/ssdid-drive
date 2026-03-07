defmodule SecureSharingWeb.API.InviteControllerTest do
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory

  alias SecureSharing.Invitations

  describe "GET /api/invite/:token" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Admin User")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "returns invitation info for valid token", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: :member,
          message: "Welcome to the team!"
        })

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      assert json_response(conn, 200)["data"] == %{
               "id" => invitation.id,
               "email" => "newuser@example.com",
               "role" => "member",
               "tenant_name" => "Test Company",
               "inviter_name" => "Admin User",
               "message" => "Welcome to the team!",
               "expires_at" => DateTime.to_iso8601(invitation.expires_at),
               "valid" => true,
               "error_reason" => nil
             }
    end

    test "returns error info for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/api/invite/invalid-token")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "not_found"
    end

    test "returns error info for expired invitation", %{conn: conn, tenant: tenant, admin: admin} do
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "expired"
    end

    test "returns error info for revoked invitation", %{conn: conn, tenant: tenant, admin: admin} do
      invitation = insert(:revoked_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "revoked"
    end

    test "returns error info for accepted invitation", %{conn: conn, tenant: tenant, admin: admin} do
      invitation = insert(:accepted_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "already_used"
    end
  end

  describe "POST /api/invite/:token/accept" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id, display_name: "Admin User")
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "accepts invitation and creates user account", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id,
          role: :member
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)["data"]
      assert response["user"]["email"] == "newuser@example.com"
      assert response["user"]["display_name"] == "New User"
      assert response["user"]["tenant_id"] == tenant.id
      assert response["user"]["role"] == "member"
      assert response["access_token"] != nil
      assert response["refresh_token"] != nil
      assert response["token_type"] == "Bearer"
      assert response["expires_in"] != nil
    end

    test "returns 404 for invalid token", %{conn: conn} do
      params = %{
        "password" => "secure_password_123",
        "public_keys" => %{}
      }

      conn = post(conn, ~p"/api/invite/invalid-token/accept", params)

      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end

    test "returns 410 for expired invitation", %{conn: conn, tenant: tenant, admin: admin} do
      invitation = insert(:expired_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      params = %{
        "password" => "secure_password_123",
        "public_keys" => %{}
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 410)
      assert response["error"]["code"] == "gone"
      assert response["error"]["message"] =~ "expired"
    end

    test "returns 410 for revoked invitation", %{conn: conn, tenant: tenant, admin: admin} do
      invitation = insert(:revoked_invitation, tenant_id: tenant.id, inviter_id: admin.id)

      params = %{
        "password" => "secure_password_123",
        "public_keys" => %{}
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 410)
      assert response["error"]["code"] == "gone"
      assert response["error"]["message"] =~ "revoked"
    end

    test "returns 409 for already accepted invitation", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      # Accept the invitation first time
      post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      # Try to accept again
      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
      assert response["error"]["message"] =~ "already been used"
    end

    test "returns 422 for password too short", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "password" => "short",
        "public_keys" => %{}
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
      assert response["error"]["details"]["password"] != nil
    end

    test "creates user with correct role from invitation", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newadminuser@example.com",
          tenant_id: tenant.id,
          role: :admin
        })

      params = %{
        "display_name" => "Admin User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)["data"]
      assert response["user"]["role"] == "admin"
    end

    # =========================================================================
    # Validation Error Tests (INV-API-034 to INV-API-048)
    # =========================================================================
    # Note: The API allows null/empty display_name and stores it as null
    # These tests verify actual API behavior

    test "accepts missing display_name and stores as null", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        # No display_name
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)
      assert response["data"]["user"]["display_name"] == nil
    end

    test "returns 422 for missing password", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        # No password
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end

    test "returns 422 for password exactly 11 characters", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        # 11 chars - too short (min is 12)
        "password" => "12345678901",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end

    test "accepts password exactly 12 characters", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        # 12 chars - minimum valid
        "password" => "123456789012",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      assert json_response(conn, 201)["data"]["user"] != nil
    end

    test "returns 422 for empty request body", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", %{})

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end

    # Note: The API currently accepts requests without public_keys and creates
    # the user anyway (returns 201). This test documents the actual behavior.
    # If public_keys should be required, this needs API-side validation.
    test "accepts missing public_keys (creates user without keys)", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        # No public_keys
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      # API accepts this request - public_keys are optional
      response = json_response(conn, 201)
      assert response["data"]["user"] != nil
    end

    # =========================================================================
    # Role Tests
    # =========================================================================

    # Note: Invitations can have manager role, but user_tenant only supports
    # member, admin, owner. Accepting an invitation with manager role fails
    # validation. This is a known limitation - manager invitations cannot
    # be accepted until the user_tenant schema is updated.

    test "creates user with admin role", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newadmin@example.com",
          tenant_id: tenant.id,
          role: :admin
        })

      params = %{
        "display_name" => "Admin User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)["data"]
      assert response["user"]["role"] == "admin"
    end

    # =========================================================================
    # Additional GET Tests
    # =========================================================================

    test "returns invitation with null message when not provided", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
          # No message
        })

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      response = json_response(conn, 200)["data"]
      assert response["message"] == nil
    end

    test "returns correct role values", %{conn: conn, tenant: tenant, admin: admin} do
      # Test admin role
      {:ok, admin_invite} =
        Invitations.create_invitation(admin, %{
          email: "admin@example.com",
          tenant_id: tenant.id,
          role: :admin
        })

      conn_admin = get(conn, ~p"/api/invite/#{admin_invite.token}")
      assert json_response(conn_admin, 200)["data"]["role"] == "admin"

      # Test manager role
      {:ok, manager_invite} =
        Invitations.create_invitation(admin, %{
          email: "manager@example.com",
          tenant_id: tenant.id,
          role: :manager
        })

      conn_manager = get(conn, ~p"/api/invite/#{manager_invite.token}")
      assert json_response(conn_manager, 200)["data"]["role"] == "manager"

      # Test member role
      {:ok, member_invite} =
        Invitations.create_invitation(admin, %{
          email: "member@example.com",
          tenant_id: tenant.id,
          role: :member
        })

      conn_member = get(conn, ~p"/api/invite/#{member_invite.token}")
      assert json_response(conn_member, 200)["data"]["role"] == "member"
    end

    test "returns valid=true for pending invitation not yet expired", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      conn = get(conn, ~p"/api/invite/#{invitation.token}")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == true
      assert response["error_reason"] == nil
    end

    # =========================================================================
    # Token Format Edge Cases
    # =========================================================================

    test "returns error for token with special characters", %{conn: conn} do
      conn = get(conn, ~p"/api/invite/abc!@#$%^&*()")

      response = json_response(conn, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "not_found"
    end

    test "returns error for empty token path", %{conn: conn} do
      # Empty path should be handled by router (404)
      conn = get(conn, "/api/invite/")

      assert conn.status == 404
    end

    # =========================================================================
    # Response Structure Tests
    # =========================================================================

    test "accept returns Bearer token type", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)["data"]
      assert response["token_type"] == "Bearer"
      assert is_integer(response["expires_in"])
      assert response["expires_in"] > 0
    end

    test "accept returns user email matching invitation", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "specific.user@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      response = json_response(conn, 201)["data"]
      assert response["user"]["email"] == "specific.user@example.com"
    end

    test "marks invitation as accepted after acceptance", %{
      conn: conn,
      tenant: tenant,
      admin: admin
    } do
      {:ok, invitation} =
        Invitations.create_invitation(admin, %{
          email: "newuser@example.com",
          tenant_id: tenant.id
        })

      params = %{
        "display_name" => "New User",
        "password" => "secure_password_123",
        "public_keys" => %{
          "ml_kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "ml_dsa" => Base.encode64(:crypto.strong_rand_bytes(32))
        },
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      post(conn, ~p"/api/invite/#{invitation.token}/accept", params)

      # Verify invitation is now marked as accepted
      conn_check = get(conn, ~p"/api/invite/#{invitation.token}")
      response = json_response(conn_check, 200)["data"]
      assert response["valid"] == false
      assert response["error_reason"] == "already_used"
    end
  end
end
