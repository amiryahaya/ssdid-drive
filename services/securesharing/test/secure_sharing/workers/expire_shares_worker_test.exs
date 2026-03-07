defmodule SecureSharing.Workers.ExpireSharesWorkerTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Workers.ExpireSharesWorker
  alias SecureSharing.Sharing

  import SecureSharing.Factory

  setup do
    tenant = insert(:tenant)
    owner = insert(:user, tenant: tenant)
    grantee = insert(:user, tenant: tenant)
    folder = insert(:root_folder, tenant: tenant, owner: owner)
    test_file = insert(:file, tenant: tenant, owner: owner, folder: folder)

    {:ok, tenant: tenant, owner: owner, grantee: grantee, test_file: test_file, folder: folder}
  end

  describe "perform/1" do
    test "expires shares past their expires_at", ctx do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)

      share =
        insert(:file_share,
          tenant: ctx.tenant,
          grantor: ctx.owner,
          grantee: ctx.grantee,
          resource_id: ctx.test_file.id,
          expires_at: past
        )

      assert :ok = ExpireSharesWorker.perform(%Oban.Job{args: %{}})

      updated = Sharing.get_share_grant(share.id)
      refute is_nil(updated.revoked_at)
    end

    test "does not expire shares without expires_at", ctx do
      share =
        insert(:file_share,
          tenant: ctx.tenant,
          grantor: ctx.owner,
          grantee: ctx.grantee,
          resource_id: ctx.test_file.id,
          expires_at: nil
        )

      assert :ok = ExpireSharesWorker.perform(%Oban.Job{args: %{}})

      updated = Sharing.get_share_grant(share.id)
      assert is_nil(updated.revoked_at)
    end

    test "does not expire shares with future expires_at", ctx do
      future =
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:microsecond)

      share =
        insert(:file_share,
          tenant: ctx.tenant,
          grantor: ctx.owner,
          grantee: ctx.grantee,
          resource_id: ctx.test_file.id,
          expires_at: future
        )

      assert :ok = ExpireSharesWorker.perform(%Oban.Job{args: %{}})

      updated = Sharing.get_share_grant(share.id)
      assert is_nil(updated.revoked_at)
    end

    test "does not double-expire already revoked shares", ctx do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)

      earlier =
        DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:microsecond)

      share =
        insert(:file_share,
          tenant: ctx.tenant,
          grantor: ctx.owner,
          grantee: ctx.grantee,
          resource_id: ctx.test_file.id,
          expires_at: past,
          revoked_at: earlier,
          revoked_by: ctx.owner
        )

      assert :ok = ExpireSharesWorker.perform(%Oban.Job{args: %{}})

      updated = Sharing.get_share_grant(share.id)
      # revoked_at should remain the original value, not be overwritten
      assert DateTime.compare(updated.revoked_at, earlier) == :eq
    end
  end
end
