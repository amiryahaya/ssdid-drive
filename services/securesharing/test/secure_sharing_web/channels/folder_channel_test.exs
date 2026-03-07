defmodule SecureSharingWeb.FolderChannelTest do
  use SecureSharingWeb.ChannelCase, async: true

  alias SecureSharingWeb.FolderChannel

  describe "join/3" do
    test "owner can join their folder channel" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      assert socket.assigns.folder_id == folder.id
    end

    test "user with share access can join folder channel" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      shared_user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)

      # Create a share grant
      insert(:share_grant,
        grantor_id: owner.id,
        grantee_id: shared_user.id,
        resource_type: :folder,
        resource_id: folder.id,
        tenant_id: tenant.id,
        permission: :read
      )

      socket = authenticated_socket(shared_user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")
    end

    test "user without access cannot join folder channel" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      other_user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)

      socket = authenticated_socket(other_user)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")
    end

    test "rejects join with invalid folder id" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, FolderChannel, "folder:invalid-uuid")
    end

    test "rejects join for non-existent folder" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)
      fake_id = Ecto.UUID.generate()

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, FolderChannel, "folder:#{fake_id}")
    end
  end

  describe "handle_in get_contents" do
    test "returns folder contents for owner" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      file = insert(:file, folder_id: folder.id, owner_id: user.id, tenant_id: tenant.id)
      subfolder = insert(:folder, parent_id: folder.id, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      ref = push(socket, "get_contents", %{})
      assert_reply ref, :ok, %{files: files, folders: folders}

      assert length(files) == 1
      assert hd(files).id == file.id

      assert length(folders) == 1
      assert hd(folders).id == subfolder.id
    end
  end

  describe "presence" do
    test "tracks user presence on join" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      # Give presence time to track
      Process.sleep(100)

      presence = SecureSharingWeb.Presence.list("folder:#{folder.id}")
      assert Map.has_key?(presence, user.id)
    end

    test "pushes presence_state after join" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      assert_push "presence_state", _state
    end
  end

  describe "broadcast helpers" do
    test "broadcast_file_added sends file_added event" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      file = insert(:file, folder_id: folder.id, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      FolderChannel.broadcast_file_added(folder.id, file)

      assert_broadcast "file_added", %{id: file_id}
      assert file_id == file.id
    end

    test "broadcast_file_removed sends file_removed event" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      file_id = Ecto.UUID.generate()
      FolderChannel.broadcast_file_removed(folder.id, file_id)

      assert_broadcast "file_removed", %{id: ^file_id}
    end

    test "broadcast_folder_added sends folder_added event" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      subfolder = insert(:folder, parent_id: folder.id, owner_id: user.id, tenant_id: tenant.id)

      socket = authenticated_socket(user)
      {:ok, _reply, _socket} = subscribe_and_join(socket, FolderChannel, "folder:#{folder.id}")

      FolderChannel.broadcast_folder_added(folder.id, subfolder)

      assert_broadcast "folder_added", %{id: subfolder_id}
      assert subfolder_id == subfolder.id
    end
  end
end
