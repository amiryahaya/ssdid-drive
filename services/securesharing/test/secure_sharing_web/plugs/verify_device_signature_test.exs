defmodule SecureSharingWeb.Plugs.VerifyDeviceSignatureTest do
  @moduledoc """
  Tests for the VerifyDeviceSignature plug.

  Tests device signature verification for authenticated requests.
  """

  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory

  alias SecureSharingWeb.Plugs.VerifyDeviceSignature
  alias SecureSharing.Devices

  describe "init/1" do
    test "sets default options" do
      opts = VerifyDeviceSignature.init([])

      assert opts.optional == false
      assert opts.max_age == 300
    end

    test "allows custom options" do
      opts = VerifyDeviceSignature.init(optional: true, max_age: 600)

      assert opts.optional == true
      assert opts.max_age == 600
    end
  end

  describe "call/2 with required verification" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      device = insert(:device, platform: :android)

      enrollment =
        insert(:device_enrollment, device_id: device.id, user_id: user.id, tenant_id: tenant.id)

      {:ok, user: user, tenant: tenant, device: device, enrollment: enrollment}
    end

    test "returns 400 when X-Device-ID header is missing", %{conn: conn, user: user} do
      opts = VerifyDeviceSignature.init([])

      conn =
        conn
        |> assign(:current_user, user)
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "missing_device_id"
    end

    test "returns 400 when X-Device-Signature header is missing", %{
      conn: conn,
      user: user,
      device: device
    } do
      opts = VerifyDeviceSignature.init([])

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", device.id)
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "missing_signature"
    end

    test "returns 400 when X-Signature-Timestamp header is missing", %{
      conn: conn,
      user: user,
      device: device
    } do
      opts = VerifyDeviceSignature.init([])

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", device.id)
        |> put_req_header("x-device-signature", "somesignature")
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "missing_timestamp"
    end

    test "returns 400 when timestamp format is invalid", %{conn: conn, user: user, device: device} do
      opts = VerifyDeviceSignature.init([])

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", device.id)
        |> put_req_header("x-device-signature", "somesignature")
        |> put_req_header("x-signature-timestamp", "not-a-number")
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "invalid_timestamp"
    end

    test "returns 401 when signature is expired", %{conn: conn, user: user, device: device} do
      opts = VerifyDeviceSignature.init(max_age: 1)
      # Use a timestamp from 10 seconds ago
      old_timestamp = System.system_time(:millisecond) - 10_000

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", device.id)
        |> put_req_header("x-device-signature", "somesignature")
        |> put_req_header("x-signature-timestamp", to_string(old_timestamp))
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "signature_expired"
    end

    test "returns 401 when user is not authenticated", %{conn: conn, device: device} do
      opts = VerifyDeviceSignature.init([])
      timestamp = System.system_time(:millisecond)

      conn =
        conn
        |> put_req_header("x-device-id", device.id)
        |> put_req_header("x-device-signature", "somesignature")
        |> put_req_header("x-signature-timestamp", to_string(timestamp))
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == "not_authenticated"
    end

    test "returns 401 when device is not enrolled for user", %{conn: conn, user: user} do
      opts = VerifyDeviceSignature.init([])
      timestamp = System.system_time(:millisecond)
      non_existent_device_id = Ecto.UUID.generate()

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", non_existent_device_id)
        |> put_req_header("x-device-signature", Base.encode64("invalid"))
        |> put_req_header("x-signature-timestamp", to_string(timestamp))
        |> Map.put(:request_path, "/api/files")
        |> Map.put(:method, "GET")
        |> VerifyDeviceSignature.call(opts)

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "call/2 with optional verification" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      {:ok, user: user, tenant: tenant}
    end

    test "passes through when headers are missing and optional is true", %{conn: conn, user: user} do
      opts = VerifyDeviceSignature.init(optional: true)

      conn =
        conn
        |> assign(:current_user, user)
        |> VerifyDeviceSignature.call(opts)

      refute conn.halted
      refute Map.has_key?(conn.assigns, :device_enrollment)
    end

    test "passes through when signature is invalid but optional is true", %{
      conn: conn,
      user: user
    } do
      opts = VerifyDeviceSignature.init(optional: true)
      timestamp = System.system_time(:millisecond)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_req_header("x-device-id", Ecto.UUID.generate())
        |> put_req_header("x-device-signature", "invalid")
        |> put_req_header("x-signature-timestamp", to_string(timestamp))
        |> Map.put(:request_path, "/api/files")
        |> Map.put(:method, "GET")
        |> VerifyDeviceSignature.call(opts)

      refute conn.halted
    end
  end

  describe "build_signature_payload/4" do
    test "builds correct payload for GET request" do
      payload = Devices.build_signature_payload("GET", "/api/files", 1_234_567_890, "")

      assert payload == "GET|/api/files|1234567890|"
    end

    test "builds correct payload for POST request with body" do
      body = ~s({"name":"test"})
      body_hash = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

      payload = Devices.build_signature_payload("POST", "/api/files", 1_234_567_890, body)

      assert payload == "POST|/api/files|1234567890|#{body_hash}"
    end
  end
end
