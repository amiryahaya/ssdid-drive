defmodule SecureSharingWeb.Controllers.Api.RecoveryControllerTest do
  @moduledoc """
  Tests for social recovery API endpoints.

  Based on test plan:
  - GET /api/recovery/config - Get recovery config
  - POST /api/recovery/setup - Setup recovery
  - DELETE /api/recovery/config - Disable recovery
  - POST /api/recovery/shares - Create recovery share
  - GET /api/recovery/shares/trustee - List trustee shares
  - GET /api/recovery/shares/created - List owner's shares
  - POST /api/recovery/shares/:id/accept - Accept share
  - POST /api/recovery/shares/:id/reject - Reject share
  - DELETE /api/recovery/shares/:id - Revoke share
  - POST /api/recovery/request - Create recovery request
  - GET /api/recovery/requests - List requests
  - GET /api/recovery/requests/pending - List pending for trustee
  - GET /api/recovery/requests/:id - Get request details
  - POST /api/recovery/requests/:id/approve - Approve request
  - POST /api/recovery/requests/:id/complete - Complete recovery
  - DELETE /api/recovery/requests/:id - Cancel request
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/recovery/config
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/recovery/config" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns recovery config if exists", %{conn: conn, user: user, tenant: tenant} do
      config = insert(:recovery_config, user_id: user.id)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/recovery/config")

      response = json_response(conn, 200)
      assert response["data"]["id"] == config.id
      assert response["data"]["threshold"]
      assert response["data"]["total_shares"]
    end

    test "returns null if no config", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/recovery/config")

      response = json_response(conn, 200)
      assert response["data"] == nil
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/recovery/config")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/setup
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/setup" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "creates recovery config", %{conn: conn, user: user, tenant: tenant} do
      params = %{"threshold" => 3, "total_shares" => 5}

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/setup", params)

      response = json_response(conn, 201)
      assert response["data"]["threshold"] == 3
      assert response["data"]["total_shares"] == 5
    end

    test "returns error for invalid threshold", %{conn: conn, user: user, tenant: tenant} do
      params = %{"threshold" => 6, "total_shares" => 5}

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/setup", params)

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end

    test "returns 409 if config already exists", %{conn: conn, user: user, tenant: tenant} do
      insert(:recovery_config, user_id: user.id)
      params = %{"threshold" => 3, "total_shares" => 5}

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/setup", params)

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/recovery/config
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/recovery/config" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)
      {:ok, tenant: tenant, user: user, config: config}
    end

    test "disables recovery config", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/recovery/config")

      assert response(conn, 204)
    end

    test "returns 404 if no config exists", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(other_user, tenant) |> delete(~p"/api/recovery/config")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/shares
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/shares" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id, email: "trustee@example.com")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: trustee.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)
      {:ok, tenant: tenant, user: user, trustee: trustee, config: config}
    end

    test "creates recovery share for trustee", %{
      conn: conn,
      user: user,
      tenant: tenant,
      trustee: trustee
    } do
      params = %{
        "trustee_id" => trustee.id,
        "encrypted_share" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "share_index" => 1
      }

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/shares", params)

      response = json_response(conn, 201)
      assert response["data"]["trustee_id"] == trustee.id
      # RecoveryShare uses accepted boolean, not status enum
      assert response["data"]["accepted"] == false
    end

    test "returns 404 for non-existent trustee", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      params = %{
        "trustee_id" => fake_id,
        "encrypted_share" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "share_index" => 1
      }

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/shares", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/recovery/shares/trustee
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/recovery/shares/trustee" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: trustee.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)

      share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: user.id,
          trustee_id: trustee.id,
          accepted: false
        )

      {:ok, tenant: tenant, trustee: trustee, share: share}
    end

    test "returns shares where user is trustee", %{
      conn: conn,
      tenant: tenant,
      trustee: trustee,
      share: share
    } do
      conn = conn |> authenticate(trustee, tenant) |> get(~p"/api/recovery/shares/trustee")

      response = json_response(conn, 200)
      share_ids = Enum.map(response["data"], & &1["id"])
      assert share.id in share_ids
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/shares/:id/accept
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/shares/:id/accept" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: trustee.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)

      share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: user.id,
          trustee_id: trustee.id,
          accepted: false
        )

      {:ok, tenant: tenant, trustee: trustee, share: share}
    end

    test "trustee can accept share", %{conn: conn, tenant: tenant, trustee: trustee, share: share} do
      conn =
        conn |> authenticate(trustee, tenant) |> post(~p"/api/recovery/shares/#{share.id}/accept")

      response = json_response(conn, 200)
      # RecoveryShare uses accepted boolean, not status enum
      assert response["data"]["accepted"] == true
    end

    test "non-trustee cannot accept share", %{conn: conn, tenant: tenant, share: share} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(other, tenant) |> post(~p"/api/recovery/shares/#{share.id}/accept")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/request
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/request" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)
      {:ok, tenant: tenant, user: user, config: config}
    end

    test "creates recovery request", %{conn: conn, user: user, tenant: tenant} do
      params = %{
        "reason" => "Lost device",
        "new_public_key" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/recovery/request", params)

      response = json_response(conn, 201)
      assert response["data"]["status"] == "pending"
    end

    test "returns 404 if no recovery config", %{conn: conn, tenant: tenant} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      params = %{
        "reason" => "Lost device",
        "new_public_key" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn = conn |> authenticate(other, tenant) |> post(~p"/api/recovery/request", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/recovery/requests
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/recovery/requests" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)
      request = insert(:recovery_request, config_id: config.id, user_id: user.id)
      {:ok, tenant: tenant, user: user, request: request}
    end

    test "returns user's recovery requests", %{
      conn: conn,
      user: user,
      tenant: tenant,
      request: request
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/recovery/requests")

      response = json_response(conn, 200)
      request_ids = Enum.map(response["data"], & &1["id"])
      assert request.id in request_ids
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/requests/:id/approve
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/requests/:id/approve" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: trustee.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)

      share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: user.id,
          trustee_id: trustee.id,
          accepted: true
        )

      request = insert(:recovery_request, config_id: config.id, user_id: user.id)
      {:ok, tenant: tenant, trustee: trustee, share: share, request: request}
    end

    test "trustee can approve request with their share", %{
      conn: conn,
      tenant: tenant,
      trustee: trustee,
      share: share,
      request: request
    } do
      params = %{
        "share_id" => share.id,
        "reencrypted_share" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
      }

      conn =
        conn
        |> authenticate(trustee, tenant)
        |> post(~p"/api/recovery/requests/#{request.id}/approve", params)

      response = json_response(conn, 201)
      assert response["data"]["trustee_id"] == trustee.id
    end

    test "non-trustee cannot approve", %{
      conn: conn,
      tenant: tenant,
      share: share,
      request: request
    } do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      params = %{
        "share_id" => share.id,
        "reencrypted_share" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
      }

      conn =
        conn
        |> authenticate(other, tenant)
        |> post(~p"/api/recovery/requests/#{request.id}/approve", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/recovery/requests/:id/complete
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/recovery/requests/:id/complete" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id, threshold: 2, total_shares: 3)

      # Create trustees and shares
      trustee1 = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: trustee1.id, tenant_id: tenant.id, role: :member)

      share1 =
        insert(:recovery_share, config_id: config.id, owner_id: user.id, trustee_id: trustee1.id)

      trustee2 = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: trustee2.id, tenant_id: tenant.id, role: :member)

      share2 =
        insert(:recovery_share, config_id: config.id, owner_id: user.id, trustee_id: trustee2.id)

      # Create request in approved status with actual approval records
      request =
        insert(:recovery_request,
          config_id: config.id,
          user_id: user.id,
          status: :approved
        )

      # Create actual approval records to satisfy threshold_reached?
      insert(:recovery_approval,
        request_id: request.id,
        share_id: share1.id,
        trustee_id: trustee1.id
      )

      insert(:recovery_approval,
        request_id: request.id,
        share_id: share2.id,
        trustee_id: trustee2.id
      )

      {:ok, tenant: tenant, user: user, request: request}
    end

    test "user can complete recovery with threshold met", %{
      conn: conn,
      user: user,
      tenant: tenant,
      request: request
    } do
      params = %{
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(16)),
        "public_keys" => %{
          "kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "sign" => Base.encode64(:crypto.strong_rand_bytes(32))
        }
      }

      conn =
        conn
        |> authenticate(user, tenant)
        |> post(~p"/api/recovery/requests/#{request.id}/complete", params)

      response = json_response(conn, 200)
      assert response["data"]["message"] == "Recovery completed successfully"
      assert response["data"]["user_id"] == user.id
      assert response["data"]["status"] == "active"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/recovery/requests/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/recovery/requests/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      config = insert(:recovery_config, user_id: user.id)

      request =
        insert(:recovery_request, config_id: config.id, user_id: user.id, status: :pending)

      {:ok, tenant: tenant, user: user, request: request}
    end

    test "user can cancel their recovery request", %{
      conn: conn,
      user: user,
      tenant: tenant,
      request: request
    } do
      conn =
        conn |> authenticate(user, tenant) |> delete(~p"/api/recovery/requests/#{request.id}")

      assert response(conn, 204)
    end

    test "other user cannot cancel request", %{conn: conn, tenant: tenant, request: request} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(other, tenant) |> delete(~p"/api/recovery/requests/#{request.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
