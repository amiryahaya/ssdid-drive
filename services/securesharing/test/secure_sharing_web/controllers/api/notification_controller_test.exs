defmodule SecureSharingWeb.Controllers.Api.NotificationControllerTest do
  @moduledoc """
  Tests for notification API endpoints.

  Based on test plan:
  - GET /api/notifications - List notifications
  - GET /api/notifications/unread_count - Get unread count
  - POST /api/notifications/:id/read - Mark as read
  - POST /api/notifications/read_all - Mark all as read
  - DELETE /api/notifications/:id - Delete notification
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/notifications
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/notifications" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns list of notifications", %{conn: conn, user: user, tenant: tenant} do
      notification1 = insert_notification(user.id, "share_received", %{message: "New share"})
      notification2 = insert_notification(user.id, "recovery_request", %{message: "Recovery"})

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/notifications")

      response = json_response(conn, 200)
      notification_ids = Enum.map(response["data"], & &1["id"])
      assert notification1.id in notification_ids
      assert notification2.id in notification_ids
    end

    test "supports pagination", %{conn: conn, user: user, tenant: tenant} do
      for i <- 1..25, do: insert_notification(user.id, "test", %{index: i})

      # Controller uses limit/offset instead of page/page_size
      # Use standard Phoenix way to pass query params
      conn =
        conn |> authenticate(user, tenant) |> get(~p"/api/notifications", %{limit: 10, offset: 0})

      response = json_response(conn, 200)
      assert length(response["data"]) <= 10
    end

    test "does not return other user's notifications", %{conn: conn, user: user, tenant: tenant} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)
      other_notification = insert_notification(other.id, "test", %{})

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/notifications")

      response = json_response(conn, 200)
      notification_ids = Enum.map(response["data"], & &1["id"])
      refute other_notification.id in notification_ids
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/notifications/unread_count
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/notifications/unread_count" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns count of unread notifications", %{conn: conn, user: user, tenant: tenant} do
      insert_notification(user.id, "test1", %{}, false)
      insert_notification(user.id, "test2", %{}, false)
      insert_notification(user.id, "test3", %{}, true)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/notifications/unread_count")

      response = json_response(conn, 200)
      assert response["data"]["unread_count"] == 2
    end

    test "returns 0 when no unread notifications", %{conn: conn, user: user, tenant: tenant} do
      insert_notification(user.id, "test", %{}, true)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/notifications/unread_count")

      response = json_response(conn, 200)
      assert response["data"]["unread_count"] == 0
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/notifications/:id/read
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/notifications/:id/read" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      notification = insert_notification(user.id, "test", %{}, false)
      {:ok, tenant: tenant, user: user, notification: notification}
    end

    test "marks notification as read", %{
      conn: conn,
      user: user,
      tenant: tenant,
      notification: notification
    } do
      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/notifications/#{notification.id}/read")

      response = json_response(conn, 200)
      # Controller returns notification_id and unread_count, not full notification
      assert response["data"]["notification_id"] == notification.id
      assert is_integer(response["data"]["unread_count"])
    end

    test "is idempotent", %{conn: conn, user: user, tenant: tenant, notification: notification} do
      # Mark read first time
      conn1 =
        conn |> authenticate(user, tenant) |> post(~p"/api/notifications/#{notification.id}/read")

      response1 = json_response(conn1, 200)
      assert response1["data"]["notification_id"] == notification.id

      # Mark read again
      conn2 =
        build_conn()
        |> authenticate(user, tenant)
        |> post(~p"/api/notifications/#{notification.id}/read")

      response2 = json_response(conn2, 200)

      # Should return same notification_id (idempotent)
      assert response1["data"]["notification_id"] == response2["data"]["notification_id"]
    end

    test "returns 404 for other user's notification", %{
      conn: conn,
      tenant: tenant,
      notification: notification
    } do
      # Returns 404 instead of 403 to avoid leaking info about other users' notifications
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      conn =
        conn
        |> authenticate(other, tenant)
        |> post(~p"/api/notifications/#{notification.id}/read")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 404 for non-existent notification", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/notifications/#{fake_id}/read")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/notifications/read_all
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/notifications/read_all" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "marks all notifications as read", %{conn: conn, user: user, tenant: tenant} do
      insert_notification(user.id, "test1", %{}, false)
      insert_notification(user.id, "test2", %{}, false)
      insert_notification(user.id, "test3", %{}, false)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/notifications/read_all")

      response = json_response(conn, 200)
      assert response["data"]["marked_count"] == 3
    end

    test "returns 0 when no unread notifications", %{conn: conn, user: user, tenant: tenant} do
      insert_notification(user.id, "test", %{}, true)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/notifications/read_all")

      response = json_response(conn, 200)
      assert response["data"]["marked_count"] == 0
    end

    test "does not affect other user's notifications", %{conn: conn, user: user, tenant: tenant} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)
      insert_notification(other.id, "other", %{}, false)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/notifications/read_all")

      response = json_response(conn, 200)
      assert response["data"]["marked_count"] == 0
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/notifications/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/notifications/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      notification = insert_notification(user.id, "test", %{})
      {:ok, tenant: tenant, user: user, notification: notification}
    end

    test "deletes notification", %{
      conn: conn,
      user: user,
      tenant: tenant,
      notification: notification
    } do
      conn =
        conn |> authenticate(user, tenant) |> delete(~p"/api/notifications/#{notification.id}")

      assert response(conn, 204)
    end

    test "returns 404 for other user's notification", %{
      conn: conn,
      tenant: tenant,
      notification: notification
    } do
      # Returns 404 instead of 403 to avoid leaking info about other users' notifications
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(other, tenant) |> delete(~p"/api/notifications/#{notification.id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 404 for non-existent notification", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/notifications/#{fake_id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp insert_notification(user_id, type, data, read \\ false) do
    read_at = if read, do: DateTime.utc_now(), else: nil

    {:ok, notification} =
      SecureSharing.Notifications.create_user_notification(user_id, %{
        type: type,
        title: "Test Notification",
        body: "Test body",
        data: data,
        read_at: read_at
      })

    notification
  end
end
