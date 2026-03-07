defmodule SecureSharingWeb.Controllers.Api.AccessRequestControllerTest do
  @moduledoc """
  Tests for share permission upgrade request endpoints.

  - POST /api/shares/:id/request-upgrade - Request permission upgrade
  - POST /api/shares/:id/approve-upgrade - Approve upgrade request
  - POST /api/shares/:id/deny-upgrade - Deny upgrade request
  - GET /api/shares/upgrade-requests - List pending requests (grantor)
  - GET /api/shares/my-upgrade-requests - List own requests
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/shares/:id/request-upgrade
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/shares/:id/request-upgrade" do
    setup :create_share_scenario

    test "creates an upgrade request for a read share", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      share: share
    } do
      conn =
        conn
        |> authenticate(grantee, tenant)
        |> post(~p"/api/shares/#{share.id}/request-upgrade", %{
          "requested_permission" => "write",
          "reason" => "Need edit access"
        })

      response = json_response(conn, 201)
      assert response["data"]["share_grant_id"] == share.id
      assert response["data"]["requester_id"] == grantee.id
      assert response["data"]["requested_permission"] == "write"
      assert response["data"]["status"] == "pending"
      assert response["data"]["reason"] == "Need edit access"
    end

    test "rejects upgrade to same or lower permission", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      share: share
    } do
      # Share is :read, requesting :read is not an upgrade
      conn =
        conn
        |> authenticate(grantee, tenant)
        |> post(~p"/api/shares/#{share.id}/request-upgrade", %{
          "requested_permission" => "read"
        })

      # nil permission from parse fails differently — falls through to bad_request
      response = json_response(conn, 400)
      assert response["error"]["code"] == "bad_request"
    end

    test "rejects request from non-grantee", %{
      conn: conn,
      grantor: grantor,
      tenant: tenant,
      share: share
    } do
      conn =
        conn
        |> authenticate(grantor, tenant)
        |> post(~p"/api/shares/#{share.id}/request-upgrade", %{
          "requested_permission" => "write"
        })

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "rejects duplicate pending request", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      share: share
    } do
      # First request succeeds
      conn
      |> authenticate(grantee, tenant)
      |> post(~p"/api/shares/#{share.id}/request-upgrade", %{
        "requested_permission" => "write"
      })
      |> json_response(201)

      # Second request fails (unique constraint on pending)
      conn =
        build_conn()
        |> authenticate(grantee, tenant)
        |> post(~p"/api/shares/#{share.id}/request-upgrade", %{
          "requested_permission" => "admin"
        })

      response = json_response(conn, 422)
      assert response["error"]
    end

    test "returns 401 for unauthenticated request", %{conn: conn, share: share} do
      conn = post(conn, ~p"/api/shares/#{share.id}/request-upgrade", %{})

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end

    test "returns 404 for non-existent share", %{conn: conn, grantee: grantee, tenant: tenant} do
      fake_id = UUIDv7.generate()

      conn =
        conn
        |> authenticate(grantee, tenant)
        |> post(~p"/api/shares/#{fake_id}/request-upgrade", %{
          "requested_permission" => "write"
        })

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/shares/:id/approve-upgrade
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/shares/:id/approve-upgrade" do
    setup :create_share_with_request

    test "approves the upgrade request and updates share permission", %{
      conn: conn,
      grantor: grantor,
      tenant: tenant,
      share: share,
      request: request
    } do
      conn =
        conn
        |> authenticate(grantor, tenant)
        |> post(~p"/api/shares/#{share.id}/approve-upgrade", %{
          "request_id" => request.id,
          "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
        })

      response = json_response(conn, 200)
      assert response["data"]["status"] == "approved"
      assert response["data"]["decided_by_id"] == grantor.id

      # Verify the share permission was actually upgraded
      updated_share = SecureSharing.Sharing.get_share_grant(share.id)
      assert updated_share.permission == :write
    end

    test "rejects approval from non-grantor/non-admin", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      share: share,
      request: request
    } do
      conn =
        conn
        |> authenticate(grantee, tenant)
        |> post(~p"/api/shares/#{share.id}/approve-upgrade", %{
          "request_id" => request.id
        })

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 400 for missing request_id", %{
      conn: conn,
      grantor: grantor,
      tenant: tenant,
      share: share
    } do
      conn =
        conn
        |> authenticate(grantor, tenant)
        |> post(~p"/api/shares/#{share.id}/approve-upgrade", %{})

      response = json_response(conn, 400)
      assert response["error"]["message"] =~ "request_id"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/shares/:id/deny-upgrade
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/shares/:id/deny-upgrade" do
    setup :create_share_with_request

    test "denies the upgrade request", %{
      conn: conn,
      grantor: grantor,
      tenant: tenant,
      share: share,
      request: request
    } do
      conn =
        conn
        |> authenticate(grantor, tenant)
        |> post(~p"/api/shares/#{share.id}/deny-upgrade", %{
          "request_id" => request.id
        })

      response = json_response(conn, 200)
      assert response["data"]["status"] == "denied"
      assert response["data"]["decided_by_id"] == grantor.id

      # Verify the share permission was NOT changed
      unchanged_share = SecureSharing.Sharing.get_share_grant(share.id)
      assert unchanged_share.permission == :read
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/shares/upgrade-requests
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/shares/upgrade-requests" do
    setup :create_share_with_request

    test "lists pending requests for the grantor", %{
      conn: conn,
      grantor: grantor,
      tenant: tenant,
      request: request
    } do
      conn = conn |> authenticate(grantor, tenant) |> get(~p"/api/shares/upgrade-requests")

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert request.id in ids
    end

    test "does not show requests for other users", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      request: request
    } do
      # Grantee is the requester, not the grantor — should see nothing here
      conn = conn |> authenticate(grantee, tenant) |> get(~p"/api/shares/upgrade-requests")

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      refute request.id in ids
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/shares/my-upgrade-requests
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/shares/my-upgrade-requests" do
    setup :create_share_with_request

    test "lists requests made by the current user", %{
      conn: conn,
      grantee: grantee,
      tenant: tenant,
      request: request
    } do
      conn = conn |> authenticate(grantee, tenant) |> get(~p"/api/shares/my-upgrade-requests")

      response = json_response(conn, 200)
      ids = Enum.map(response["data"], & &1["id"])
      assert request.id in ids
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Setup Helpers
  # ═══════════════════════════════════════════════════════════════════════════

  defp create_share_scenario(_context) do
    tenant = insert(:tenant, name: "Upgrade Test Tenant")
    grantor = insert(:user, tenant_id: tenant.id)
    grantee = insert(:user, tenant_id: tenant.id)
    insert(:user_tenant, user_id: grantor.id, tenant_id: tenant.id, role: :member)
    insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

    root = insert(:root_folder, owner_id: grantor.id, tenant_id: tenant.id)
    file = insert(:file, owner_id: grantor.id, tenant_id: tenant.id, folder_id: root.id)

    share =
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: grantor.id,
        grantee_id: grantee.id,
        resource_id: file.id,
        permission: :read
      )

    {:ok, tenant: tenant, grantor: grantor, grantee: grantee, shared_file: file, share: share}
  end

  defp create_share_with_request(context) do
    {:ok, data} = create_share_scenario(context)

    request =
      insert(:access_request,
        tenant_id: data[:tenant].id,
        share_grant_id: data[:share].id,
        requester_id: data[:grantee].id,
        requested_permission: :write,
        reason: "Need to update the report"
      )

    {:ok, Keyword.put(data, :request, request)}
  end

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
