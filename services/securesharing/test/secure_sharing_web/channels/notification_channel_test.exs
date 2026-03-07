defmodule SecureSharingWeb.NotificationChannelTest do
  use SecureSharingWeb.ChannelCase, async: true

  alias SecureSharingWeb.NotificationChannel

  describe "join/3" do
    test "user can join their own notification channel" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)

      {:ok, _reply, socket} =
        subscribe_and_join(socket, NotificationChannel, "notification:#{user.id}")

      assert socket.assigns.user_id == user.id
    end

    test "user cannot join another user's notification channel" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      other_user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, NotificationChannel, "notification:#{other_user.id}")
    end
  end

  describe "broadcast helpers" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, NotificationChannel, "notification:#{user.id}")

      {:ok, user: user}
    end

    test "broadcast_share_received sends share_received event", %{user: user} do
      share = %{
        id: Ecto.UUID.generate(),
        grantor_id: Ecto.UUID.generate(),
        resource_type: :file,
        resource_id: Ecto.UUID.generate(),
        permission: :read,
        created_at: DateTime.utc_now()
      }

      NotificationChannel.broadcast_share_received(user.id, share)

      assert_broadcast "share_received", %{id: share_id, resource_type: :file}
      assert share_id == share.id
    end

    test "broadcast_share_revoked sends share_revoked event", %{user: user} do
      share = %{
        id: Ecto.UUID.generate(),
        resource_type: :folder,
        resource_id: Ecto.UUID.generate()
      }

      NotificationChannel.broadcast_share_revoked(user.id, share)

      assert_broadcast "share_revoked", %{id: share_id, resource_type: :folder}
      assert share_id == share.id
    end

    test "broadcast_recovery_request sends recovery_request event", %{user: user} do
      request = %{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        status: :pending,
        created_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      NotificationChannel.broadcast_recovery_request(user.id, request)

      assert_broadcast "recovery_request", %{id: request_id, status: :pending}
      assert request_id == request.id
    end

    test "broadcast_recovery_approval sends recovery_approval event", %{user: user} do
      approval = %{
        request_id: Ecto.UUID.generate(),
        trustee_id: Ecto.UUID.generate()
      }

      progress = %{
        current_approvals: 2,
        threshold: 3,
        status: :pending
      }

      NotificationChannel.broadcast_recovery_approval(user.id, approval, progress)

      assert_broadcast "recovery_approval", %{
        request_id: _,
        current_approvals: 2,
        threshold: 3
      }
    end

    test "broadcast_recovery_complete sends recovery_complete event", %{user: user} do
      request = %{id: Ecto.UUID.generate()}

      NotificationChannel.broadcast_recovery_complete(user.id, request)

      assert_broadcast "recovery_complete", %{request_id: request_id}
      assert request_id == request.id
    end

    test "broadcast_notification sends generic notification", %{user: user} do
      NotificationChannel.broadcast_notification(
        user.id,
        "custom_event",
        "Test Title",
        "Test Body",
        %{custom_data: "test"}
      )

      assert_broadcast "custom_event", payload
      assert payload.title == "Test Title"
      assert payload.body == "Test Body"
      assert payload.custom_data == "test"
    end
  end
end
