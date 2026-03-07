defmodule SecureSharing.AuditTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Audit
  alias SecureSharing.Audit.AuditEvent

  import SecureSharing.Factory

  describe "create_event/1" do
    test "creates an audit event with valid attrs" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login",
        resource_type: "user",
        resource_id: user.id,
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0",
        metadata: %{"browser" => "Chrome"},
        status: "success"
      }

      assert {:ok, event} = Audit.create_event(attrs)
      assert event.tenant_id == tenant.id
      assert event.user_id == user.id
      assert event.action == "user.login"
      assert event.resource_type == "user"
      assert event.ip_address == "192.168.1.1"
      assert event.status == "success"
    end

    test "creates event without user_id for system events" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        action: "tenant.create",
        resource_type: "tenant",
        resource_id: tenant.id,
        status: "success"
      }

      assert {:ok, event} = Audit.create_event(attrs)
      assert is_nil(event.user_id)
    end

    test "creates event with failure status and error message" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        action: "user.login_failed",
        resource_type: "user",
        status: "failure",
        error_message: "Invalid credentials"
      }

      assert {:ok, event} = Audit.create_event(attrs)
      assert event.status == "failure"
      assert event.error_message == "Invalid credentials"
    end

    test "validates required fields" do
      assert {:error, changeset} = Audit.create_event(%{})
      assert "can't be blank" in errors_on(changeset).tenant_id
      assert "can't be blank" in errors_on(changeset).action
      assert "can't be blank" in errors_on(changeset).resource_type
    end

    test "validates action inclusion" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        action: "invalid.action",
        resource_type: "user",
        status: "success"
      }

      assert {:error, changeset} = Audit.create_event(attrs)
      assert "is invalid" in errors_on(changeset).action
    end
  end

  describe "list_events/2" do
    setup do
      tenant = insert(:tenant)
      user1 = insert(:user, tenant_id: tenant.id)
      user2 = insert(:user, tenant_id: tenant.id)

      # Create various events
      {:ok, e1} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user1.id,
          action: "user.login",
          resource_type: "user",
          resource_id: user1.id,
          status: "success"
        })

      {:ok, e2} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user1.id,
          action: "file.create",
          resource_type: "file",
          status: "success"
        })

      {:ok, e3} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user2.id,
          action: "user.login_failed",
          resource_type: "user",
          status: "failure"
        })

      %{tenant: tenant, user1: user1, user2: user2, events: [e1, e2, e3]}
    end

    test "lists all events for a tenant", %{tenant: tenant} do
      events = Audit.list_events(tenant.id)
      assert length(events) == 3
    end

    test "filters by user_id", %{tenant: tenant, user1: user1} do
      events = Audit.list_events(tenant.id, user_id: user1.id)
      assert length(events) == 2
      assert Enum.all?(events, fn e -> e.user_id == user1.id end)
    end

    test "filters by action", %{tenant: tenant} do
      events = Audit.list_events(tenant.id, action: "user.login")
      assert length(events) == 1
      assert hd(events).action == "user.login"
    end

    test "filters by action prefix with wildcard", %{tenant: tenant} do
      events = Audit.list_events(tenant.id, action: "user.*")
      assert length(events) == 2
      assert Enum.all?(events, fn e -> String.starts_with?(e.action, "user.") end)
    end

    test "filters by resource_type", %{tenant: tenant} do
      events = Audit.list_events(tenant.id, resource_type: "file")
      assert length(events) == 1
      assert hd(events).resource_type == "file"
    end

    test "filters by status", %{tenant: tenant} do
      events = Audit.list_events(tenant.id, status: "failure")
      assert length(events) == 1
      assert hd(events).status == "failure"
    end

    test "applies limit", %{tenant: tenant} do
      events = Audit.list_events(tenant.id, limit: 2)
      assert length(events) == 2
    end

    test "applies offset", %{tenant: tenant} do
      all_events = Audit.list_events(tenant.id, order: :desc)
      offset_events = Audit.list_events(tenant.id, offset: 1, order: :desc)

      assert length(offset_events) == 2
      assert hd(offset_events).id == Enum.at(all_events, 1).id
    end

    test "orders by inserted_at", %{tenant: tenant} do
      asc_events = Audit.list_events(tenant.id, order: :asc)
      desc_events = Audit.list_events(tenant.id, order: :desc)

      assert hd(asc_events).id == List.last(desc_events).id
    end

    test "does not return events from other tenants", %{tenant: tenant} do
      other_tenant = insert(:tenant)
      other_user = insert(:user, tenant_id: other_tenant.id)

      {:ok, _} =
        Audit.create_event(%{
          tenant_id: other_tenant.id,
          user_id: other_user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })

      events = Audit.list_events(tenant.id)
      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.tenant_id == tenant.id end)
    end
  end

  describe "count_events/2" do
    test "counts events for tenant" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      for _ <- 1..5 do
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })
      end

      assert Audit.count_events(tenant.id) == 5
    end

    test "counts with filters" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login",
        resource_type: "user",
        status: "success"
      })

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login",
        resource_type: "user",
        status: "success"
      })

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "file.create",
        resource_type: "file",
        status: "success"
      })

      assert Audit.count_events(tenant.id, action: "user.login") == 2
      assert Audit.count_events(tenant.id, resource_type: "file") == 1
    end
  end

  describe "get_event/2" do
    test "returns event for tenant" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      {:ok, event} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })

      found = Audit.get_event(tenant.id, event.id)
      assert found.id == event.id
    end

    test "returns nil for event from different tenant" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)
      user = insert(:user, tenant_id: tenant1.id)

      {:ok, event} =
        Audit.create_event(%{
          tenant_id: tenant1.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })

      assert is_nil(Audit.get_event(tenant2.id, event.id))
    end
  end

  describe "get_statistics/2" do
    test "returns statistics for tenant" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login",
        resource_type: "user",
        status: "success"
      })

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login",
        resource_type: "user",
        status: "success"
      })

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "file.create",
        resource_type: "file",
        status: "success"
      })

      Audit.create_event(%{
        tenant_id: tenant.id,
        user_id: user.id,
        action: "user.login_failed",
        resource_type: "user",
        status: "failure"
      })

      stats = Audit.get_statistics(tenant.id)

      assert stats.total == 4
      assert stats.by_action["user.login"] == 2
      assert stats.by_action["file.create"] == 1
      assert stats.by_status["success"] == 3
      assert stats.by_status["failure"] == 1
      assert stats.by_resource_type["user"] == 3
      assert stats.by_resource_type["file"] == 1
    end
  end

  describe "export_events/2" do
    test "exports events with formatted data" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      {:ok, _} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          resource_id: user.id,
          ip_address: "192.168.1.1",
          status: "success"
        })

      [exported] = Audit.export_events(tenant.id)

      assert exported.action == "user.login"
      assert exported.user_email == user.email
      assert exported.ip_address == "192.168.1.1"
      assert exported.status == "success"
    end
  end

  describe "delete_old_events/2" do
    test "deletes events older than specified days" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      # Create an old event by manipulating inserted_at
      {:ok, old_event} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })

      # Update the timestamp to be old (this is a test helper approach)
      old_timestamp = DateTime.utc_now() |> DateTime.add(-100, :day)

      Repo.update_all(
        from(e in AuditEvent, where: e.id == ^old_event.id),
        set: [inserted_at: old_timestamp]
      )

      # Create a recent event
      {:ok, _recent_event} =
        Audit.create_event(%{
          tenant_id: tenant.id,
          user_id: user.id,
          action: "user.login",
          resource_type: "user",
          status: "success"
        })

      # Delete events older than 30 days
      {:ok, count} = Audit.delete_old_events(tenant.id, 30)

      assert count == 1
      assert Audit.count_events(tenant.id) == 1
    end
  end

  describe "AuditEvent schema" do
    test "valid_actions returns list of actions" do
      actions = AuditEvent.valid_actions()
      assert is_list(actions)
      assert "user.login" in actions
      assert "file.create" in actions
    end

    test "valid_resource_types returns list of types" do
      types = AuditEvent.valid_resource_types()
      assert is_list(types)
      assert "user" in types
      assert "file" in types
    end

    test "valid_statuses returns list of statuses" do
      statuses = AuditEvent.valid_statuses()
      assert statuses == ~w(success failure)
    end
  end
end
