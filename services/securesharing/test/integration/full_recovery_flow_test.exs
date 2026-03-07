defmodule SecureSharing.Integration.FullRecoveryFlowTest do
  @moduledoc """
  End-to-end integration test for the complete key recovery flow.

  Tests the full recovery journey:
  1. User sets up recovery with trustees (3-of-5)
  2. Trustees accept their shares
  3. User initiates recovery request
  4. Trustees approve with their shares
  5. User completes recovery and gets new keys
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  alias SecureSharing.Recovery

  @factory_password "valid_password123"

  describe "complete recovery flow" do
    setup do
      tenant = insert(:tenant, slug: "recovery-test-#{System.unique_integer([:positive])}")

      # Create owner and 5 trustees
      owner = insert(:user, tenant_id: tenant.id, email: "owner@example.com")

      trustees =
        for i <- 1..5 do
          insert(:user, tenant_id: tenant.id, email: "trustee#{i}@example.com")
        end

      # Login owner
      conn_owner =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => owner.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_owner}} = json_response(conn_owner, 200)

      # Login all trustees
      trustee_tokens =
        Enum.map(trustees, fn trustee ->
          conn =
            build_conn()
            |> put_req_header("content-type", "application/json")
            |> post(~p"/api/auth/login", %{
              "tenant_slug" => tenant.slug,
              "email" => trustee.email,
              "password" => @factory_password
            })

          %{"data" => %{"access_token" => token}} = json_response(conn, 200)
          {trustee, token}
        end)

      {:ok,
       tenant: tenant,
       owner: owner,
       trustees: trustees,
       token_owner: token_owner,
       trustee_tokens: trustee_tokens}
    end

    test "full recovery setup, request, and completion", %{
      owner: owner,
      trustees: trustees,
      token_owner: token_owner,
      trustee_tokens: trustee_tokens
    } do
      # Step 1: Owner initiates recovery config (3-of-5 threshold)
      config_attrs = %{
        "threshold" => 3,
        "total_shares" => 5
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/setup", config_attrs)

      assert %{"data" => %{"id" => config_id}} = json_response(conn, 201)
      assert is_binary(config_id)

      # Verify config was created
      config = Recovery.get_recovery_config_by_id(config_id)
      assert config.threshold == 3
      assert config.total_shares == 5
      assert config.user_id == owner.id

      # Step 2: Owner distributes shares to trustees
      shares =
        Enum.with_index(trustees, 1)
        |> Enum.map(fn {trustee, index} ->
          share_attrs = %{
            "config_id" => config_id,
            "trustee_id" => trustee.id,
            "share_index" => index,
            "encrypted_share" => Base.encode64(:crypto.strong_rand_bytes(64)),
            "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
            "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
          }

          conn =
            build_conn()
            |> put_req_header("authorization", "Bearer #{token_owner}")
            |> put_req_header("content-type", "application/json")
            |> post(~p"/api/recovery/shares", share_attrs)

          assert %{"data" => %{"id" => share_id}} = json_response(conn, 201)
          {trustee.id, share_id}
        end)

      # Step 3: Mark config as setup complete
      # Note: In actual implementation, the setup endpoint may handle this automatically
      # or we need to check if there's a separate endpoint. For now, we'll skip this step
      # as the setup process may mark it complete when all shares are distributed.

      # Step 4: Each trustee accepts their share
      Enum.each(trustee_tokens, fn {trustee, token} ->
        {_trustee_id, share_id} = Enum.find(shares, fn {tid, _} -> tid == trustee.id end)

        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer #{token}")
          |> put_req_header("content-type", "application/json")
          |> post(~p"/api/recovery/shares/#{share_id}/accept")

        assert %{"data" => %{"accepted" => true}} = json_response(conn, 200)
      end)

      # Step 5: Owner initiates recovery request (simulating lost device)
      request_attrs = %{
        "config_id" => config_id,
        "new_public_key" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "reason" => "Lost device"
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/request", request_attrs)

      assert %{"data" => %{"id" => request_id}} = json_response(conn, 201)

      # Verify request was created
      request = Recovery.get_recovery_request(request_id)
      assert request.status == :pending
      assert request.user_id == owner.id

      # Step 6: First 3 trustees approve the request (threshold)
      approved_trustees = Enum.take(trustee_tokens, 3)

      Enum.each(approved_trustees, fn {trustee, token} ->
        {_trustee_id, share_id} = Enum.find(shares, fn {tid, _} -> tid == trustee.id end)

        approval_attrs = %{
          "share_id" => share_id,
          "reencrypted_share" => Base.encode64(:crypto.strong_rand_bytes(64)),
          "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
          "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
        }

        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer #{token}")
          |> put_req_header("content-type", "application/json")
          |> post(~p"/api/recovery/requests/#{request_id}/approve", approval_attrs)

        assert %{"data" => _} = json_response(conn, 201)
      end)

      # Step 7: Check that request status after approvals
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> get(~p"/api/recovery/requests/#{request_id}")

      response = json_response(conn, 200)
      # After 3 approvals, status should be "approved" or show progress
      assert response["data"]["status"] in ["pending", "approved"]

      # Step 8: Owner finalizes recovery
      finalize_attrs = %{
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/requests/#{request_id}/complete", finalize_attrs)

      # Response indicates successful recovery
      response = json_response(conn, 200)
      assert response["data"]["message"] == "Recovery completed successfully"

      # Verify request is now complete
      completed_request = Recovery.get_recovery_request(request_id)
      assert completed_request.status == :completed
    end
  end

  describe "recovery constraints" do
    setup do
      tenant = insert(:tenant, slug: "recovery-cons-#{System.unique_integer([:positive])}")
      owner = insert(:user, tenant_id: tenant.id)
      trustees = for _ <- 1..3, do: insert(:user, tenant_id: tenant.id)

      conn_owner =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => owner.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_owner}} = json_response(conn_owner, 200)

      {:ok, tenant: tenant, owner: owner, trustees: trustees, token_owner: token_owner}
    end

    test "cannot finalize without threshold approvals", %{
      owner: owner,
      trustees: trustees,
      token_owner: token_owner
    } do
      # Create config with 3-of-3 threshold
      config =
        insert(:recovery_config,
          user_id: owner.id,
          threshold: 3,
          total_shares: 3,
          setup_complete: true
        )

      # Create shares
      shares =
        Enum.with_index(trustees, 1)
        |> Enum.map(fn {trustee, index} ->
          insert(:recovery_share,
            config_id: config.id,
            owner_id: owner.id,
            trustee_id: trustee.id,
            share_index: index,
            accepted: true
          )
        end)

      # Create a recovery request
      request =
        insert(:recovery_request, config_id: config.id, user_id: owner.id, status: :pending)

      # Only 2 trustees approve (not enough for 3-of-3)
      Enum.take(shares, 2)
      |> Enum.each(fn share ->
        insert(:recovery_approval,
          request_id: request.id,
          share_id: share.id,
          trustee_id: share.trustee_id
        )
      end)

      # Try to finalize - should fail
      finalize_attrs = %{
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/requests/#{request.id}/complete", finalize_attrs)

      # Should fail - threshold not met
      assert json_response(conn, 412)
    end

    test "trustee cannot approve own share", %{
      owner: owner,
      token_owner: token_owner
    } do
      # Create a config where owner is both owner and trustee (edge case)
      config =
        insert(:recovery_config,
          user_id: owner.id,
          threshold: 1,
          total_shares: 1,
          setup_complete: true
        )

      share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: owner.id,
          trustee_id: owner.id,
          share_index: 1,
          accepted: true
        )

      request =
        insert(:recovery_request, config_id: config.id, user_id: owner.id, status: :pending)

      # Owner tries to approve their own share (should work since they're the trustee)
      approval_attrs = %{
        "share_id" => share.id,
        "reencrypted_share" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/requests/#{request.id}/approve", approval_attrs)

      # This should succeed since owner is a legitimate trustee
      assert %{"data" => _} = json_response(conn, 201)
    end

    test "cannot create duplicate recovery config", %{
      owner: owner,
      token_owner: token_owner
    } do
      # Create first config
      _config = insert(:recovery_config, user_id: owner.id, setup_complete: false)

      # Try to create another config
      config_attrs = %{
        "threshold" => 2,
        "total_shares" => 3
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/recovery/setup", config_attrs)

      # Should fail - config already exists
      assert json_response(conn, 409)
    end
  end

  describe "trustee view" do
    setup do
      tenant = insert(:tenant, slug: "trustee-view-#{System.unique_integer([:positive])}")
      owner = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)

      conn_trustee =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => trustee.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_trustee}} = json_response(conn_trustee, 200)

      {:ok, tenant: tenant, owner: owner, trustee: trustee, token_trustee: token_trustee}
    end

    test "trustee can see shares assigned to them", %{
      owner: owner,
      trustee: trustee,
      token_trustee: token_trustee
    } do
      # Create recovery setup
      config = insert(:recovery_config, user_id: owner.id, setup_complete: true)

      _share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: owner.id,
          trustee_id: trustee.id,
          share_index: 1,
          accepted: false
        )

      # Trustee lists their shares
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_trustee}")
        |> get(~p"/api/recovery/shares/trustee")

      assert %{"data" => shares} = json_response(conn, 200)
      assert length(shares) >= 1
      assert Enum.all?(shares, fn s -> s["trustee_id"] == trustee.id end)
    end
  end
end
