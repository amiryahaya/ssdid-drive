defmodule SecureSharingWeb.Controllers.Api.DeviceControllerTest do
  @moduledoc """
  Tests for device enrollment and management API endpoints.

  Based on test plan:
  - POST /api/devices/enroll - Enroll device
  - GET /api/devices - List enrolled devices
  - GET /api/devices/:id - Get device details
  - PUT /api/devices/:id - Update device
  - DELETE /api/devices/:id - Revoke device
  - POST /api/devices/:id/push - Register push notifications
  - DELETE /api/devices/:id/push - Unregister push notifications
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/devices/enroll
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/devices/enroll" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "enrolls new device with valid data", %{conn: conn, user: user, tenant: tenant} do
      params = valid_enrollment_params()

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/devices/enroll", params)

      response = json_response(conn, 201)
      assert response["data"]["device_name"] == params["device_name"]
      # Platform is in the nested device object
      assert response["data"]["device"]["platform"] == params["platform"]
      assert response["data"]["status"] == "active"
    end

    test "returns error for missing required fields", %{conn: conn, user: user, tenant: tenant} do
      params = %{"device_name" => "My Phone"}

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/devices/enroll", params)

      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      params = valid_enrollment_params()

      conn = post(conn, ~p"/api/devices/enroll", params)

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/devices
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/devices" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns list of enrolled devices", %{conn: conn, user: user, tenant: tenant} do
      # Create some device enrollments for user
      enrollment1 = create_device_enrollment(user, tenant, "Phone 1")
      enrollment2 = create_device_enrollment(user, tenant, "Tablet")

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/devices")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      device_ids = Enum.map(response["data"], & &1["id"])
      assert enrollment1.id in device_ids
      assert enrollment2.id in device_ids
    end

    test "does not return other user's devices", %{conn: conn, user: user, tenant: tenant} do
      # Create enrollment for another user
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_enrollment = create_device_enrollment(other_user, tenant, "Other Phone")

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/devices")

      response = json_response(conn, 200)
      device_ids = Enum.map(response["data"], & &1["id"])
      refute other_enrollment.id in device_ids
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/devices")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/devices/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/devices/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "My Phone")
      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    test "returns device details", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == enrollment.id
      assert response["data"]["device_name"] == "My Phone"
    end

    test "returns 403 for other user's device", %{
      conn: conn,
      tenant: tenant,
      enrollment: enrollment
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(other_user, tenant) |> get(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 404 for non-existent device", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/devices/#{fake_id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/devices/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/devices/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "Old Name")
      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    test "updates device name", %{conn: conn, user: user, tenant: tenant, enrollment: enrollment} do
      params = %{"device_name" => "New Name"}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/devices/#{enrollment.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["device_name"] == "New Name"
    end

    test "returns 403 for other user's device", %{
      conn: conn,
      tenant: tenant,
      enrollment: enrollment
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      params = %{"device_name" => "Hacked Name"}

      conn =
        conn |> authenticate(other_user, tenant) |> put(~p"/api/devices/#{enrollment.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/devices/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/devices/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "Device to Delete")
      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    test "revokes device enrollment", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "revoked"
    end

    test "accepts revocation reason", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      params = %{"reason" => "Lost device"}

      conn =
        conn
        |> authenticate(user, tenant)
        |> delete(~p"/api/devices/#{enrollment.id}?#{URI.encode_query(params)}")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "revoked"
    end

    test "returns 403 for other user's device", %{
      conn: conn,
      tenant: tenant,
      enrollment: enrollment
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(other_user, tenant) |> delete(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/devices/:id/push
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/devices/:id/push" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "Push Device")
      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    @tag :external_service
    test "registers push player_id", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      params = %{"player_id" => "onesignal-player-id-123"}

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/devices/#{enrollment.id}/push", params)

      response = json_response(conn, 200)
      assert response["data"]["push_player_id"] == "onesignal-player-id-123"
    end

    test "returns 403 for other user's device", %{
      conn: conn,
      tenant: tenant,
      enrollment: enrollment
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      params = %{"player_id" => "hacker-player-id"}

      conn =
        conn
        |> authenticate(other_user, tenant)
        |> post(~p"/api/devices/#{enrollment.id}/push", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/devices/:id/push
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/devices/:id/push" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "Push Device")
      # Simulate having a push player_id
      {:ok, enrollment} =
        SecureSharing.Devices.update_push_player_id(enrollment, "existing-player-id")

      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    @tag :external_service
    test "unregisters push notifications", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/devices/#{enrollment.id}/push")

      response = json_response(conn, 200)
      assert response["data"]["push_player_id"] == nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/devices/:id/attest
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/devices/:id/attest" do
    setup do
      tenant = insert(:tenant, name: "Attestation Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      enrollment = create_device_enrollment(user, tenant, "Attest Test Device")
      {:ok, tenant: tenant, user: user, enrollment: enrollment}
    end

    test "accepts attestation for android device", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      attestation_blob = :crypto.strong_rand_bytes(256)

      conn =
        conn
        |> authenticate(user, tenant)
        |> post(~p"/api/devices/#{enrollment.id}/attest", %{
          "attestation" => Base.encode64(attestation_blob)
        })

      response = json_response(conn, 200)
      assert response["data"]["device"]["trust_level"] == "high"
      assert response["data"]["device"]["attestation_verified_at"] != nil
    end

    test "returns 400 for missing attestation data", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      conn =
        conn
        |> authenticate(user, tenant)
        |> post(~p"/api/devices/#{enrollment.id}/attest", %{})

      response = json_response(conn, 400)
      assert response["error"]["code"] == "bad_request"
    end

    test "returns 400 for invalid base64 attestation", %{
      conn: conn,
      user: user,
      tenant: tenant,
      enrollment: enrollment
    } do
      conn =
        conn
        |> authenticate(user, tenant)
        |> post(~p"/api/devices/#{enrollment.id}/attest", %{
          "attestation" => "not-valid-base64!!!"
        })

      response = json_response(conn, 400)
      assert response["error"]["code"] == "bad_request"
    end

    test "returns 401 for unauthenticated request", %{conn: conn, enrollment: enrollment} do
      conn =
        post(conn, ~p"/api/devices/#{enrollment.id}/attest", %{
          "attestation" => Base.encode64("test")
        })

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end

    test "returns 403 when attesting another user's device", %{
      conn: conn,
      tenant: tenant,
      enrollment: enrollment
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)

      conn =
        conn
        |> authenticate(other_user, tenant)
        |> post(~p"/api/devices/#{enrollment.id}/attest", %{
          "attestation" => Base.encode64(:crypto.strong_rand_bytes(256))
        })

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

  defp valid_enrollment_params do
    %{
      "device_fingerprint" => "sha256:#{Base.encode16(:crypto.strong_rand_bytes(32))}",
      "platform" => "android",
      "device_info" => %{
        "model" => "Pixel 8",
        "os_version" => "Android 14",
        "app_version" => "1.0.0"
      },
      # kaz_sign requires at least 1000 bytes for device_public_key
      "device_public_key" => Base.encode64(:crypto.strong_rand_bytes(1024)),
      "key_algorithm" => "kaz_sign",
      "device_name" => "Test Device"
    }
  end

  defp create_device_enrollment(user, tenant, device_name) do
    {:ok, enrollment} =
      SecureSharing.Devices.enroll_device(%{
        user_id: user.id,
        tenant_id: tenant.id,
        device_fingerprint: "sha256:#{Base.encode16(:crypto.strong_rand_bytes(32))}",
        platform: "android",
        device_info: %{"model" => "Test"},
        # kaz_sign requires at least 1000 bytes
        device_public_key: :crypto.strong_rand_bytes(1024),
        key_algorithm: :kaz_sign,
        device_name: device_name
      })

    enrollment
  end
end
