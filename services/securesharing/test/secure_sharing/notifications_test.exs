defmodule SecureSharing.NotificationsTest do
  @moduledoc """
  Tests for the Notifications context module.

  Tests notification dispatch functions and user notification management.
  """

  use SecureSharing.DataCase, async: true
  use Oban.Testing, repo: SecureSharing.Repo

  import SecureSharing.Factory

  alias SecureSharing.Notifications
  alias SecureSharing.Notifications.Worker

  describe "notify_share_received/2" do
    test "enqueues notification job" do
      user_id = Ecto.UUID.generate()

      params = %{
        from_name: "John Doe",
        item_name: "Project Files",
        share_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_share_received(user_id, params)

      # Verify a job was enqueued
      assert [job] = all_enqueued(worker: Worker)
      assert job.args["type"] == "share_received"
      assert job.args["user_ids"] == [user_id]
      assert job.args["title"] == "New Share"
    end

    test "truncates long item names" do
      user_id = Ecto.UUID.generate()

      params = %{
        from_name: "John",
        item_name: "This is a very long file name that exceeds thirty characters",
        share_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_share_received(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert String.contains?(job.args["body"], "...")
    end
  end

  describe "notify_share_accepted/2" do
    test "enqueues notification job" do
      user_id = Ecto.UUID.generate()

      params = %{
        recipient_name: "Jane Doe",
        item_name: "Documents",
        share_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_share_accepted(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert job.args["type"] == "share_accepted"
      assert job.args["title"] == "Share Accepted"
    end
  end

  describe "notify_recovery_request/2" do
    test "enqueues notification for multiple trustees" do
      trustee_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      params = %{
        requester_name: "Alice",
        request_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_recovery_request(trustee_ids, params)

      [job] = all_enqueued(worker: Worker)
      assert job.args["type"] == "recovery_request"
      assert job.args["user_ids"] == trustee_ids
      assert job.args["title"] == "Recovery Request"
    end
  end

  describe "notify_recovery_approved/2" do
    test "enqueues notification with progress" do
      user_id = Ecto.UUID.generate()

      params = %{
        trustee_name: "Bob",
        shares_received: 2,
        threshold: 3,
        request_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_recovery_approved(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert String.contains?(job.args["body"], "(2/3)")
    end
  end

  describe "notify_recovery_denied/2" do
    test "enqueues notification" do
      user_id = Ecto.UUID.generate()

      params = %{
        trustee_name: "Charlie",
        request_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_recovery_denied(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert job.args["title"] == "Recovery Denied"
    end
  end

  describe "notify_recovery_complete/2" do
    test "enqueues notification" do
      user_id = Ecto.UUID.generate()

      assert :ok = Notifications.notify_recovery_complete(user_id, %{})

      [job] = all_enqueued(worker: Worker)
      assert job.args["title"] == "Recovery Complete"
    end
  end

  describe "notify_device_enrolled/2" do
    test "enqueues notification with device info" do
      user_id = Ecto.UUID.generate()

      params = %{
        device_name: "My iPhone",
        platform: "iOS",
        device_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_device_enrolled(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert job.args["title"] == "New Device"
      assert String.contains?(job.args["body"], "iOS")
    end
  end

  describe "notify_file_ready/2" do
    test "enqueues notification" do
      user_id = Ecto.UUID.generate()

      params = %{
        file_name: "report.pdf",
        file_id: Ecto.UUID.generate()
      }

      assert :ok = Notifications.notify_file_ready(user_id, params)

      [job] = all_enqueued(worker: Worker)
      assert job.args["title"] == "Download Ready"
    end
  end

  describe "user notification management" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id)

      {:ok, user: user, tenant: tenant}
    end

    test "create_user_notification/2 creates notification", %{user: user} do
      attrs = %{
        title: "Test Notification",
        body: "This is a test",
        type: "share_received"
      }

      assert {:ok, notification} = Notifications.create_user_notification(user.id, attrs)
      assert notification.user_id == user.id
      assert notification.title == "Test Notification"
      assert is_nil(notification.read_at)
    end

    test "list_user_notifications/2 returns notifications in order", %{user: user} do
      # Create multiple notifications
      {:ok, _n1} =
        Notifications.create_user_notification(user.id, %{
          title: "First",
          body: "Body 1",
          type: "share_received"
        })

      {:ok, _n2} =
        Notifications.create_user_notification(user.id, %{
          title: "Second",
          body: "Body 2",
          type: "share_accepted"
        })

      notifications = Notifications.list_user_notifications(user.id)

      assert length(notifications) == 2
      # Most recent first
      assert hd(notifications).title == "Second"
    end

    test "list_user_notifications/2 respects pagination", %{user: user} do
      for i <- 1..5 do
        Notifications.create_user_notification(user.id, %{
          title: "Notification #{i}",
          body: "Body",
          type: "share_received"
        })
      end

      page1 = Notifications.list_user_notifications(user.id, limit: 2, offset: 0)
      page2 = Notifications.list_user_notifications(user.id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2
      assert hd(page1).id != hd(page2).id
    end

    test "list_user_notifications/2 filters unread only", %{user: user} do
      {:ok, n1} =
        Notifications.create_user_notification(user.id, %{
          title: "Unread",
          body: "Body",
          type: "share_received"
        })

      {:ok, _n2} =
        Notifications.create_user_notification(user.id, %{
          title: "Read",
          body: "Body",
          type: "share_accepted"
        })

      # Mark one as read
      Notifications.mark_notification_read(user.id, n1.id)

      unread = Notifications.list_user_notifications(user.id, unread_only: true)
      all = Notifications.list_user_notifications(user.id, unread_only: false)

      assert length(unread) == 1
      assert length(all) == 2
    end

    test "count_unread_notifications/1 counts correctly", %{user: user} do
      {:ok, n1} =
        Notifications.create_user_notification(user.id, %{
          title: "One",
          body: "Body",
          type: "share_received"
        })

      {:ok, _n2} =
        Notifications.create_user_notification(user.id, %{
          title: "Two",
          body: "Body",
          type: "share_received"
        })

      assert Notifications.count_unread_notifications(user.id) == 2

      Notifications.mark_notification_read(user.id, n1.id)

      assert Notifications.count_unread_notifications(user.id) == 1
    end

    test "mark_notification_read/2 marks as read", %{user: user} do
      {:ok, notification} =
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })

      assert is_nil(notification.read_at)

      assert {:ok, updated} = Notifications.mark_notification_read(user.id, notification.id)
      refute is_nil(updated.read_at)
    end

    test "mark_notification_read/2 is idempotent", %{user: user} do
      {:ok, notification} =
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })

      {:ok, first_update} = Notifications.mark_notification_read(user.id, notification.id)
      {:ok, second_update} = Notifications.mark_notification_read(user.id, notification.id)

      assert first_update.read_at == second_update.read_at
    end

    test "mark_notification_read/2 returns error for nonexistent notification", %{user: user} do
      assert {:error, :not_found} =
               Notifications.mark_notification_read(user.id, Ecto.UUID.generate())
    end

    test "mark_all_notifications_read/1 marks all as read", %{user: user} do
      for _ <- 1..3 do
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })
      end

      assert Notifications.count_unread_notifications(user.id) == 3

      {count, _} = Notifications.mark_all_notifications_read(user.id)
      assert count == 3

      assert Notifications.count_unread_notifications(user.id) == 0
    end

    test "dismiss_notification/2 dismisses notification", %{user: user} do
      {:ok, notification} =
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })

      assert {:ok, dismissed} = Notifications.dismiss_notification(user.id, notification.id)
      refute is_nil(dismissed.dismissed_at)

      # Dismissed notifications should not appear in list
      notifications = Notifications.list_user_notifications(user.id)
      assert length(notifications) == 0
    end

    test "get_user_notification/2 returns notification for owner", %{user: user} do
      {:ok, notification} =
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })

      assert Notifications.get_user_notification(user.id, notification.id) != nil
    end

    test "get_user_notification/2 returns nil for other user", %{user: user, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)

      {:ok, notification} =
        Notifications.create_user_notification(user.id, %{
          title: "Test",
          body: "Body",
          type: "share_received"
        })

      assert Notifications.get_user_notification(other_user.id, notification.id) == nil
    end
  end
end
