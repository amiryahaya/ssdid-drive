defmodule SecureSharing.Sharing.AccessRequestTest do
  @moduledoc """
  Tests for access request (permission upgrade) context functions.
  """
  use SecureSharing.DataCase, async: true

  import SecureSharing.Factory
  alias SecureSharing.Sharing

  describe "request_upgrade/3" do
    setup :create_share_scenario

    test "creates a pending upgrade request", %{share: share, grantee: grantee} do
      assert {:ok, request} =
               Sharing.request_upgrade(share, grantee, %{
                 requested_permission: :write,
                 reason: "Need edit access"
               })

      assert request.status == :pending
      assert request.requested_permission == :write
      assert request.requester_id == grantee.id
      assert request.share_grant_id == share.id
    end

    test "rejects request from non-grantee", %{share: share, grantor: grantor} do
      assert {:error, :forbidden} =
               Sharing.request_upgrade(share, grantor, %{requested_permission: :write})
    end

    test "rejects downgrade request", %{share: share, grantee: grantee} do
      # The share has :read permission. Requesting :read is not an upgrade.
      assert {:error, {:bad_request, _}} =
               Sharing.request_upgrade(share, grantee, %{requested_permission: :read})
    end

    test "rejects same-level request", %{tenant: tenant, grantor: grantor, grantee: grantee, shared_file: shared_file} do
      # Create a second file in the same folder using existing root
      folder_id = shared_file.folder_id
      file = insert(:file, owner_id: grantor.id, tenant_id: tenant.id, folder_id: folder_id)

      write_share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: grantor.id,
          grantee_id: grantee.id,
          resource_id: file.id,
          permission: :write
        )

      assert {:error, {:bad_request, _}} =
               Sharing.request_upgrade(write_share, grantee, %{requested_permission: :read})
    end

    test "rejects request on revoked share", %{share: share, grantee: grantee, grantor: grantor} do
      {:ok, _} = Sharing.revoke_share(share, grantor)
      revoked_share = Sharing.get_share_grant(share.id)

      assert {:error, {:bad_request, _}} =
               Sharing.request_upgrade(revoked_share, grantee, %{requested_permission: :write})
    end
  end

  describe "approve_upgrade/3" do
    setup :create_share_with_request

    test "approves and upgrades the share permission", %{
      request: request,
      grantor: grantor,
      share: share
    } do
      assert {:ok, result} = Sharing.approve_upgrade(request, grantor, %{})
      assert result.request.status == :approved
      assert result.share.permission == :write

      # Verify in DB
      updated_share = Sharing.get_share_grant(share.id)
      assert updated_share.permission == :write
    end

    test "rejects approval from unauthorized user", %{request: request, grantee: grantee} do
      assert {:error, :forbidden} = Sharing.approve_upgrade(request, grantee, %{})
    end
  end

  describe "deny_upgrade/2" do
    setup :create_share_with_request

    test "denies the request and keeps share permission", %{
      request: request,
      grantor: grantor,
      share: share
    } do
      assert {:ok, denied} = Sharing.deny_upgrade(request, grantor)
      assert denied.status == :denied

      # Share permission unchanged
      unchanged = Sharing.get_share_grant(share.id)
      assert unchanged.permission == :read
    end
  end

  describe "list_pending_requests_for_grantor/1" do
    setup :create_share_with_request

    test "returns pending requests for shares the user created", %{
      grantor: grantor,
      request: request
    } do
      requests = Sharing.list_pending_requests_for_grantor(grantor)
      assert length(requests) == 1
      assert hd(requests).id == request.id
    end

    test "does not return approved/denied requests", %{
      grantor: grantor,
      request: request
    } do
      {:ok, _} = Sharing.approve_upgrade(request, grantor, %{})

      requests = Sharing.list_pending_requests_for_grantor(grantor)
      assert length(requests) == 0
    end
  end

  # Setup helpers

  defp create_share_scenario(_context) do
    tenant = insert(:tenant)
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
        requested_permission: :write
      )

    {:ok, Keyword.put(data, :request, request)}
  end
end
