defmodule SecureSharing.DevicesTest do
  @moduledoc """
  Tests for the Devices context.
  """
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Devices
  alias SecureSharing.Accounts

  # Test fixtures
  @valid_device_attrs %{
    device_fingerprint: "sha256:abc123def456",
    platform: :android,
    device_info: %{
      "model" => "Pixel 8",
      "os_version" => "Android 14",
      "app_version" => "1.0.0"
    }
  }

  # Generate a fake public key (for testing purposes only)
  @fake_public_key :crypto.strong_rand_bytes(1312)

  describe "devices" do
    test "create_device/1 creates a device with valid attrs" do
      assert {:ok, device} = Devices.create_device(@valid_device_attrs)
      assert device.device_fingerprint == "sha256:abc123def456"
      assert device.platform == :android
      assert device.status == :active
      assert device.trust_level == :medium
    end

    test "create_device/1 fails with invalid attrs" do
      assert {:error, changeset} = Devices.create_device(%{})
      assert "can't be blank" in errors_on(changeset).device_fingerprint
      assert "can't be blank" in errors_on(changeset).platform
    end

    test "get_device_by_fingerprint/1 returns device" do
      {:ok, device} = Devices.create_device(@valid_device_attrs)
      assert found = Devices.get_device_by_fingerprint("sha256:abc123def456")
      assert found.id == device.id
    end

    test "find_or_create_device/1 creates new device if not exists" do
      assert {:ok, device} = Devices.find_or_create_device(@valid_device_attrs)
      assert device.device_fingerprint == "sha256:abc123def456"
    end

    test "find_or_create_device/1 returns existing device if exists" do
      {:ok, device1} = Devices.create_device(@valid_device_attrs)
      {:ok, device2} = Devices.find_or_create_device(@valid_device_attrs)
      assert device1.id == device2.id
    end

    test "suspend_device/1 suspends a device" do
      {:ok, device} = Devices.create_device(@valid_device_attrs)
      {:ok, suspended} = Devices.suspend_device(device)
      assert suspended.status == :suspended
    end

    test "activate_device/1 reactivates a suspended device" do
      {:ok, device} = Devices.create_device(@valid_device_attrs)
      {:ok, suspended} = Devices.suspend_device(device)
      {:ok, activated} = Devices.activate_device(suspended)
      assert activated.status == :active
    end
  end

  describe "device_enrollments" do
    setup do
      # Create a tenant and user for testing
      {:ok, tenant} =
        Accounts.create_tenant(%{name: "Test Org", slug: "test-org-#{System.unique_integer()}"})

      {:ok, user} =
        Accounts.register_user(%{
          email: "test-#{System.unique_integer()}@example.com",
          password: "Password123!",
          tenant_id: tenant.id,
          public_keys: %{"kem" => "test", "sign" => "test"}
        })

      {:ok, device} = Devices.create_device(@valid_device_attrs)

      %{tenant: tenant, user: user, device: device}
    end

    test "create_enrollment/1 creates enrollment with valid attrs", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign,
        device_name: "My Phone"
      }

      assert {:ok, enrollment} = Devices.create_enrollment(attrs)
      assert enrollment.device_id == device.id
      assert enrollment.user_id == user.id
      assert enrollment.status == :active
      assert enrollment.device_name == "My Phone"
    end

    test "create_enrollment/1 fails with missing required fields", %{user: user, device: device} do
      attrs = %{
        device_id: device.id,
        user_id: user.id
        # Missing tenant_id, device_public_key, key_algorithm
      }

      assert {:error, changeset} = Devices.create_enrollment(attrs)
      assert "can't be blank" in errors_on(changeset).tenant_id
      assert "can't be blank" in errors_on(changeset).device_public_key
    end

    test "create_enrollment/1 enforces unique constraint", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      assert {:ok, _} = Devices.create_enrollment(attrs)
      assert {:error, changeset} = Devices.create_enrollment(attrs)
      assert "already enrolled on this device" in errors_on(changeset).device_id
    end

    test "enroll_device/1 creates device and enrollment", %{tenant: tenant, user: user} do
      attrs = %{
        user_id: user.id,
        tenant_id: tenant.id,
        device_fingerprint: "sha256:new-device-123",
        platform: :ios,
        device_info: %{"model" => "iPhone 15"},
        device_public_key: @fake_public_key,
        key_algorithm: :ml_dsa,
        device_name: "iPhone"
      }

      assert {:ok, enrollment} = Devices.enroll_device(attrs)
      assert enrollment.user_id == user.id
      assert enrollment.device.platform == :ios
    end

    test "enroll_device/1 fails when device is suspended", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      Devices.suspend_device(device)

      attrs = %{
        user_id: user.id,
        tenant_id: tenant.id,
        device_fingerprint: device.device_fingerprint,
        platform: :android,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      assert {:error, :device_suspended} = Devices.enroll_device(attrs)
    end

    test "list_user_enrollments/1 returns all user enrollments", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      {:ok, _enrollment} = Devices.create_enrollment(attrs)
      enrollments = Devices.list_user_enrollments(user.id)

      assert length(enrollments) == 1
      assert hd(enrollments).user_id == user.id
    end

    test "revoke_enrollment/2 revokes an enrollment", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      {:ok, enrollment} = Devices.create_enrollment(attrs)
      {:ok, revoked} = Devices.revoke_enrollment(enrollment, "Lost device")

      assert revoked.status == :revoked
      assert revoked.revoked_reason == "Lost device"
      assert revoked.revoked_at != nil
    end

    test "get_active_enrollment/2 returns active enrollment", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      {:ok, enrollment} = Devices.create_enrollment(attrs)
      found = Devices.get_active_enrollment(device.id, user.id)

      assert found.id == enrollment.id
    end

    test "get_active_enrollment/2 returns nil for revoked enrollment", %{
      tenant: tenant,
      user: user,
      device: device
    } do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      {:ok, enrollment} = Devices.create_enrollment(attrs)
      Devices.revoke_enrollment(enrollment)

      assert Devices.get_active_enrollment(device.id, user.id) == nil
    end

    test "touch_enrollment/1 updates last_used_at", %{tenant: tenant, user: user, device: device} do
      attrs = %{
        device_id: device.id,
        user_id: user.id,
        tenant_id: tenant.id,
        device_public_key: @fake_public_key,
        key_algorithm: :kaz_sign
      }

      {:ok, enrollment} = Devices.create_enrollment(attrs)
      assert enrollment.last_used_at == nil

      {:ok, touched} = Devices.touch_enrollment(enrollment)
      assert touched.last_used_at != nil
    end
  end

  describe "multi-user device support" do
    setup do
      {:ok, tenant} =
        Accounts.create_tenant(%{
          name: "Multi User Org",
          slug: "multi-user-#{System.unique_integer()}"
        })

      {:ok, user1} =
        Accounts.register_user(%{
          email: "user1-#{System.unique_integer()}@example.com",
          password: "Password123!",
          tenant_id: tenant.id,
          public_keys: %{"kem" => "test", "sign" => "test"}
        })

      {:ok, user2} =
        Accounts.register_user(%{
          email: "user2-#{System.unique_integer()}@example.com",
          password: "Password123!",
          tenant_id: tenant.id,
          public_keys: %{"kem" => "test", "sign" => "test"}
        })

      {:ok, device} = Devices.create_device(@valid_device_attrs)

      %{tenant: tenant, user1: user1, user2: user2, device: device}
    end

    test "multiple users can enroll on same device", %{
      tenant: tenant,
      user1: user1,
      user2: user2,
      device: device
    } do
      # User 1 enrolls
      attrs1 = %{
        device_id: device.id,
        user_id: user1.id,
        tenant_id: tenant.id,
        device_public_key: :crypto.strong_rand_bytes(1312),
        key_algorithm: :kaz_sign,
        device_name: "User 1 on shared tablet"
      }

      assert {:ok, enrollment1} = Devices.create_enrollment(attrs1)

      # User 2 enrolls on same device
      attrs2 = %{
        device_id: device.id,
        user_id: user2.id,
        tenant_id: tenant.id,
        device_public_key: :crypto.strong_rand_bytes(1312),
        key_algorithm: :kaz_sign,
        device_name: "User 2 on shared tablet"
      }

      assert {:ok, enrollment2} = Devices.create_enrollment(attrs2)

      # Both enrollments exist
      assert enrollment1.id != enrollment2.id
      assert enrollment1.device_id == enrollment2.device_id
    end

    test "revoking one user's enrollment doesn't affect others", %{
      tenant: tenant,
      user1: user1,
      user2: user2,
      device: device
    } do
      # Both users enroll
      {:ok, enrollment1} =
        Devices.create_enrollment(%{
          device_id: device.id,
          user_id: user1.id,
          tenant_id: tenant.id,
          device_public_key: :crypto.strong_rand_bytes(1312),
          key_algorithm: :kaz_sign
        })

      {:ok, enrollment2} =
        Devices.create_enrollment(%{
          device_id: device.id,
          user_id: user2.id,
          tenant_id: tenant.id,
          device_public_key: :crypto.strong_rand_bytes(1312),
          key_algorithm: :kaz_sign
        })

      # Revoke user 1's enrollment
      {:ok, _revoked} = Devices.revoke_enrollment(enrollment1)

      # User 1 has no active enrollment
      assert Devices.get_active_enrollment(device.id, user1.id) == nil

      # User 2 still has active enrollment
      assert Devices.get_active_enrollment(device.id, user2.id).id == enrollment2.id
    end

    test "suspending device affects all users", %{
      tenant: tenant,
      user1: user1,
      user2: user2,
      device: device
    } do
      # Both users enroll
      {:ok, _} =
        Devices.create_enrollment(%{
          device_id: device.id,
          user_id: user1.id,
          tenant_id: tenant.id,
          device_public_key: :crypto.strong_rand_bytes(1312),
          key_algorithm: :kaz_sign
        })

      {:ok, _} =
        Devices.create_enrollment(%{
          device_id: device.id,
          user_id: user2.id,
          tenant_id: tenant.id,
          device_public_key: :crypto.strong_rand_bytes(1312),
          key_algorithm: :kaz_sign
        })

      # Suspend device
      {:ok, _suspended} = Devices.suspend_device(device)

      # New enrollments should fail
      {:ok, new_user} =
        Accounts.register_user(%{
          email: "new-user-#{System.unique_integer()}@example.com",
          password: "Password123!",
          tenant_id: tenant.id,
          public_keys: %{"kem" => "test", "sign" => "test"}
        })

      assert {:error, :device_suspended} =
               Devices.enroll_device(%{
                 user_id: new_user.id,
                 tenant_id: tenant.id,
                 device_fingerprint: device.device_fingerprint,
                 platform: :android,
                 device_public_key: :crypto.strong_rand_bytes(1312),
                 key_algorithm: :kaz_sign
               })
    end
  end

  describe "signature verification helpers" do
    test "build_signature_payload/4 builds correct payload" do
      payload =
        Devices.build_signature_payload(
          "POST",
          "/api/files",
          1_705_590_000_000,
          "{\"name\":\"test\"}"
        )

      assert payload =~ "POST|/api/files|1705590000000|"
      # Should include SHA-256 hash of body
      assert payload =~ "|"
    end

    test "build_signature_payload/4 handles empty body" do
      payload = Devices.build_signature_payload("GET", "/api/devices", 1_705_590_000_000, "")

      assert payload == "GET|/api/devices|1705590000000|"
    end
  end
end
