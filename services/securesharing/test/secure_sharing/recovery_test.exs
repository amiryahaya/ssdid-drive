defmodule SecureSharing.RecoveryTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Recovery
  alias SecureSharing.Recovery.{RecoveryRequest, Shamir}

  describe "Shamir Secret Sharing" do
    test "split/3 creates n shares from a secret" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 3, 5)

      assert length(shares) == 5

      # Each share should have an index and data of same length as secret
      for {index, share_data} <- shares do
        assert index >= 1 and index <= 5
        assert byte_size(share_data) == 32
      end
    end

    test "combine/1 reconstructs secret from k shares" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 3, 5)

      # Take any 3 shares
      three_shares = Enum.take(shares, 3)
      {:ok, recovered} = Shamir.combine(three_shares)

      assert recovered == secret
    end

    test "combine/1 works with different share combinations" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 3, 5)

      # Try different combinations of 3 shares
      combinations = [
        Enum.take(shares, 3),
        Enum.drop(shares, 2),
        [Enum.at(shares, 0), Enum.at(shares, 2), Enum.at(shares, 4)]
      ]

      for combination <- combinations do
        {:ok, recovered} = Shamir.combine(combination)
        assert recovered == secret
      end
    end

    test "combine/1 fails with insufficient shares" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 3, 5)

      # Only 2 shares - should produce wrong result
      two_shares = Enum.take(shares, 2)
      {:ok, recovered} = Shamir.combine(two_shares)

      # With < k shares, result is random (not the original secret)
      refute recovered == secret
    end

    test "verify/3 returns true when shares can reconstruct" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 3, 5)

      assert Shamir.verify(secret, shares, 3) == true
    end

    test "split/3 handles various secret sizes" do
      for size <- [16, 32, 64, 128, 256] do
        secret = :crypto.strong_rand_bytes(size)
        {:ok, shares} = Shamir.split(secret, 2, 3)
        {:ok, recovered} = Shamir.combine(Enum.take(shares, 2))
        assert recovered == secret
      end
    end

    test "split/3 with threshold equal to total" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 5, 5)
      {:ok, recovered} = Shamir.combine(shares)

      assert recovered == secret
    end

    test "split/3 with minimum threshold" do
      secret = :crypto.strong_rand_bytes(32)

      {:ok, shares} = Shamir.split(secret, 1, 5)
      {:ok, recovered} = Shamir.combine([Enum.at(shares, 0)])

      assert recovered == secret
    end
  end

  describe "recovery configuration" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user}
    end

    test "setup_recovery/2 creates a recovery config", %{user: user} do
      {:ok, config} = Recovery.setup_recovery(user, %{threshold: 3, total_shares: 5})

      assert config.user_id == user.id
      assert config.threshold == 3
      assert config.total_shares == 5
      assert config.setup_complete == false
    end

    test "setup_recovery/2 enforces one config per user", %{user: user} do
      {:ok, _} = Recovery.setup_recovery(user)
      {:error, changeset} = Recovery.setup_recovery(user)

      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "setup_recovery/2 validates threshold <= total", %{user: user} do
      {:error, changeset} = Recovery.setup_recovery(user, %{threshold: 6, total_shares: 5})

      assert "must be less than or equal to total_shares" in errors_on(changeset).threshold
    end

    test "get_recovery_config/1 returns config", %{user: user} do
      {:ok, config} = Recovery.setup_recovery(user)

      found = Recovery.get_recovery_config(user)
      assert found.id == config.id
    end

    test "complete_recovery_setup/1 marks setup complete", %{user: user} do
      {:ok, config} = Recovery.setup_recovery(user)

      {:ok, updated} = Recovery.complete_recovery_setup(config)
      assert updated.setup_complete == true
    end
  end

  describe "recovery shares" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      {:ok, config} = Recovery.setup_recovery(owner)

      {:ok, tenant: tenant, owner: owner, trustee: trustee, config: config}
    end

    test "create_share/4 creates a share for trustee", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, share} = Recovery.create_share(config, owner, trustee, attrs)

      assert share.config_id == config.id
      assert share.owner_id == owner.id
      assert share.trustee_id == trustee.id
      assert share.share_index == 1
      assert share.accepted == false
    end

    test "create_share/4 prevents self-trustee", %{config: config, owner: owner} do
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:error, changeset} = Recovery.create_share(config, owner, owner, attrs)
      assert "cannot be your own trustee" in errors_on(changeset).trustee_id
    end

    test "create_share/4 enforces unique trustee per owner", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, _} = Recovery.create_share(config, owner, trustee, attrs)

      attrs2 = Map.put(attrs, :share_index, 2)
      {:error, changeset} = Recovery.create_share(config, owner, trustee, attrs2)
      assert "has already been taken" in errors_on(changeset).owner_id
    end

    test "accept_share/1 marks share as accepted", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, share} = Recovery.create_share(config, owner, trustee, attrs)
      {:ok, accepted} = Recovery.accept_share(share)

      assert accepted.accepted == true
      assert accepted.accepted_at != nil
    end

    test "list_trustee_shares/1 returns shares held by trustee", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, _} = Recovery.create_share(config, owner, trustee, attrs)

      shares = Recovery.list_trustee_shares(trustee)
      assert length(shares) == 1
    end

    test "list_owner_shares/1 returns shares for owner's recovery", %{
      config: config,
      owner: owner,
      tenant: tenant
    } do
      trustee1 = insert(:user, tenant_id: tenant.id)
      trustee2 = insert(:user, tenant_id: tenant.id)

      for {trustee, index} <- [{trustee1, 1}, {trustee2, 2}] do
        attrs = %{
          share_index: index,
          encrypted_share: :crypto.strong_rand_bytes(64),
          kem_ciphertext: :crypto.strong_rand_bytes(128),
          signature: :crypto.strong_rand_bytes(256)
        }

        Recovery.create_share(config, owner, trustee, attrs)
      end

      shares = Recovery.list_owner_shares(owner)
      assert length(shares) == 2
    end

    test "create_share/4 accepts string share_index from controller params", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      # Simulate controller params where values come as strings
      attrs = %{
        "share_index" => "1",
        "encrypted_share" => :crypto.strong_rand_bytes(64),
        "kem_ciphertext" => :crypto.strong_rand_bytes(128),
        "signature" => :crypto.strong_rand_bytes(256)
      }

      {:ok, share} = Recovery.create_share(config, owner, trustee, attrs)

      assert share.share_index == 1
    end

    test "create_share/4 returns error for invalid string share_index", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        "share_index" => "abc",
        "encrypted_share" => :crypto.strong_rand_bytes(64),
        "kem_ciphertext" => :crypto.strong_rand_bytes(128),
        "signature" => :crypto.strong_rand_bytes(256)
      }

      assert {:error, :invalid_share_index} = Recovery.create_share(config, owner, trustee, attrs)
    end

    test "create_share/4 returns error for float string share_index", %{
      config: config,
      owner: owner,
      trustee: trustee
    } do
      attrs = %{
        "share_index" => "1.5",
        "encrypted_share" => :crypto.strong_rand_bytes(64),
        "kem_ciphertext" => :crypto.strong_rand_bytes(128),
        "signature" => :crypto.strong_rand_bytes(256)
      }

      assert {:error, :invalid_share_index} = Recovery.create_share(config, owner, trustee, attrs)
    end
  end

  describe "recovery requests" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      {:ok, config} = Recovery.setup_recovery(owner)

      {:ok, tenant: tenant, owner: owner, config: config}
    end

    test "create_recovery_request/3 creates a request", %{owner: owner} do
      new_public_key = :crypto.strong_rand_bytes(128)

      {:ok, request} =
        Recovery.create_recovery_request(owner, new_public_key, reason: "Lost device")

      assert request.user_id == owner.id
      assert request.new_public_key == new_public_key
      assert request.reason == "Lost device"
      assert request.status == :pending
      assert request.expires_at != nil
    end

    test "create_recovery_request/3 fails without config", %{tenant: tenant} do
      user_without_config = insert(:user, tenant_id: tenant.id)
      new_public_key = :crypto.strong_rand_bytes(128)

      {:error, :no_recovery_config} =
        Recovery.create_recovery_request(user_without_config, new_public_key)
    end

    test "list_pending_requests_for_trustee/1 returns relevant requests", %{
      owner: owner,
      config: config,
      tenant: tenant
    } do
      trustee = insert(:user, tenant_id: tenant.id)

      # Create a share for trustee
      attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, _share} = Recovery.create_share(config, owner, trustee, attrs)

      # Create a recovery request
      new_public_key = :crypto.strong_rand_bytes(128)
      {:ok, _request} = Recovery.create_recovery_request(owner, new_public_key)

      # Trustee should see the request
      requests = Recovery.list_pending_requests_for_trustee(trustee)
      assert length(requests) == 1
    end

    test "verify_request/2 marks request as verified", %{owner: owner, tenant: tenant} do
      admin = insert(:user, tenant_id: tenant.id)
      new_public_key = :crypto.strong_rand_bytes(128)

      {:ok, request} = Recovery.create_recovery_request(owner, new_public_key)
      {:ok, verified} = Recovery.verify_request(request, admin)

      assert verified.verified_by_id == admin.id
      assert verified.verified_at != nil
    end
  end

  describe "recovery approvals" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      {:ok, config} = Recovery.setup_recovery(owner, %{threshold: 2, total_shares: 3})

      # Create share
      share_attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, share} = Recovery.create_share(config, owner, trustee, share_attrs)
      # Accept the share (required before approval)
      {:ok, share} = Recovery.accept_share(share)

      # Create recovery request
      new_public_key = :crypto.strong_rand_bytes(128)
      {:ok, request} = Recovery.create_recovery_request(owner, new_public_key)

      {:ok,
       tenant: tenant,
       owner: owner,
       trustee: trustee,
       config: config,
       share: share,
       request: request}
    end

    test "approve_recovery/4 creates an approval", %{
      request: request,
      share: share,
      trustee: trustee
    } do
      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, approval} = Recovery.approve_recovery(request, share, trustee, attrs)

      assert approval.request_id == request.id
      assert approval.share_id == share.id
      assert approval.trustee_id == trustee.id
    end

    test "approve_recovery/4 fails if trustee doesn't own share", %{
      request: request,
      share: share,
      tenant: tenant
    } do
      other_user = insert(:user, tenant_id: tenant.id)

      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:error, :not_share_owner} = Recovery.approve_recovery(request, share, other_user, attrs)
    end

    test "threshold_reached?/1 detects when enough approvals", %{
      owner: owner,
      config: config,
      request: request,
      share: share,
      trustee: trustee,
      tenant: tenant
    } do
      # First approval
      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, _} = Recovery.approve_recovery(request, share, trustee, attrs)

      # Threshold is 2, we have 1 approval
      assert Recovery.threshold_reached?(request) == false

      # Create second trustee and share
      trustee2 = insert(:user, tenant_id: tenant.id)

      share2_attrs = %{
        share_index: 2,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, share2} = Recovery.create_share(config, owner, trustee2, share2_attrs)
      {:ok, share2} = Recovery.accept_share(share2)

      # Second approval
      {:ok, _} = Recovery.approve_recovery(request, share2, trustee2, attrs)

      # Reload request and check
      request = Recovery.get_recovery_request!(request.id)
      assert Recovery.threshold_reached?(request) == true
    end

    test "get_recovery_progress/1 returns progress info", %{
      request: request,
      share: share,
      trustee: trustee
    } do
      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, _} = Recovery.approve_recovery(request, share, trustee, attrs)

      progress = Recovery.get_recovery_progress(request)

      assert progress.approvals == 1
      assert progress.threshold == 2
      assert progress.total_shares == 3
      assert progress.threshold_reached == false
      assert progress.percentage == 50
    end

    test "complete_recovery/1 marks request completed", %{request: request} do
      {:ok, completed} = Recovery.complete_recovery(request)

      assert completed.status == :completed
      assert completed.completed_at != nil
    end

    test "approve_recovery/4 fails if share config doesn't match request config", %{
      request: request,
      trustee: trustee,
      tenant: tenant
    } do
      # Create a different owner with their own config
      other_owner = insert(:user, tenant_id: tenant.id)
      {:ok, other_config} = Recovery.setup_recovery(other_owner, %{threshold: 2, total_shares: 3})

      # Create share for the other config
      share_attrs = %{
        share_index: 1,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, other_share} = Recovery.create_share(other_config, other_owner, trustee, share_attrs)
      {:ok, other_share} = Recovery.accept_share(other_share)

      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      # Should fail because share belongs to different config than request
      assert {:error, :share_config_mismatch} =
               Recovery.approve_recovery(request, other_share, trustee, attrs)
    end

    test "approve_recovery/4 fails if request is expired", %{
      share: share,
      trustee: trustee,
      config: config
    } do
      # Create an expired request
      expired_request =
        insert(:recovery_request,
          config_id: config.id,
          user_id: config.user_id,
          new_public_key: :crypto.strong_rand_bytes(128),
          expires_at: DateTime.utc_now() |> DateTime.add(-1, :day)
        )

      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :request_expired} =
               Recovery.approve_recovery(expired_request, share, trustee, attrs)
    end

    test "approve_recovery/4 fails if request status is not approvable", %{
      share: share,
      trustee: trustee,
      config: config
    } do
      # Create a completed request
      completed_request =
        insert(:recovery_request,
          config_id: config.id,
          user_id: config.user_id,
          new_public_key: :crypto.strong_rand_bytes(128),
          status: :completed
        )

      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :request_not_approvable} =
               Recovery.approve_recovery(completed_request, share, trustee, attrs)
    end

    test "approve_recovery/4 fails if share not accepted", %{
      request: request,
      owner: owner,
      tenant: tenant
    } do
      # Create a new trustee and unaccepted share
      new_trustee = insert(:user, tenant_id: tenant.id)
      config = Recovery.get_recovery_config(owner)

      share_attrs = %{
        share_index: 2,
        encrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      {:ok, unaccepted_share} = Recovery.create_share(config, owner, new_trustee, share_attrs)
      # Note: NOT calling accept_share

      attrs = %{
        reencrypted_share: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :share_not_accepted} =
               Recovery.approve_recovery(request, unaccepted_share, new_trustee, attrs)
    end
  end

  describe "RecoveryRequest helpers" do
    test "active?/1 returns true for pending non-expired request" do
      request = %RecoveryRequest{
        status: :pending,
        expires_at: DateTime.utc_now() |> DateTime.add(1, :day)
      }

      assert RecoveryRequest.active?(request) == true
    end

    test "active?/1 returns false for expired request" do
      request = %RecoveryRequest{
        status: :pending,
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      }

      assert RecoveryRequest.active?(request) == false
    end

    test "active?/1 returns false for completed request" do
      request = %RecoveryRequest{
        status: :completed,
        expires_at: DateTime.utc_now() |> DateTime.add(1, :day)
      }

      assert RecoveryRequest.active?(request) == false
    end
  end
end
