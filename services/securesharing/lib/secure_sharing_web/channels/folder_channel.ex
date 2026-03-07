defmodule SecureSharingWeb.FolderChannel do
  @moduledoc """
  Channel for real-time folder updates.

  Broadcasts events when:
  - Files are added/removed/updated
  - Subfolders are added/removed
  - Presence changes (who's viewing)

  Topic format: "folder:{folder_id}"
  """

  use SecureSharingWeb, :channel

  alias SecureSharing.Files
  alias SecureSharing.Sharing
  alias SecureSharingWeb.Presence

  @impl true
  def join("folder:" <> folder_id, _params, socket) do
    user = socket.assigns.current_user

    with {:ok, uuid} <- Ecto.UUID.cast(folder_id),
         folder when not is_nil(folder) <- Files.get_folder(uuid),
         true <- has_access?(user, folder) do
      send(self(), :after_join)

      socket =
        socket
        |> assign(:folder_id, uuid)
        |> assign(:folder, folder)

      {:ok, socket}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track presence
    {:ok, _} = Presence.track_user(socket, socket.assigns.folder_id)

    # Push current presence state to the joining user
    push(socket, "presence_state", Presence.list(socket))

    {:noreply, socket}
  end

  @impl true
  def handle_in("get_contents", _params, socket) do
    folder = socket.assigns.folder
    user = socket.assigns.current_user

    if has_access?(user, folder) do
      files = Files.list_folder_files(folder)
      subfolders = Files.list_child_folders(folder)

      {:reply, {:ok, %{files: serialize_files(files), folders: serialize_folders(subfolders)}},
       socket}
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Presence automatically cleans up on disconnect
    {:ok, socket}
  end

  # Check if user has access to folder (owner or share)
  defp has_access?(user, folder) do
    folder.owner_id == user.id || Sharing.has_folder_access?(user, folder)
  end

  defp serialize_files(files) do
    Enum.map(files, fn file ->
      %{
        id: file.id,
        encrypted_metadata: Base.encode64(file.encrypted_metadata || <<>>),
        blob_size: file.blob_size,
        status: file.status,
        created_at: file.created_at
      }
    end)
  end

  defp serialize_folders(folders) do
    Enum.map(folders, fn folder ->
      %{
        id: folder.id,
        encrypted_metadata: Base.encode64(folder.encrypted_metadata || <<>>),
        is_root: folder.is_root,
        created_at: folder.created_at
      }
    end)
  end

  # Broadcast helpers (called from other parts of the app)

  @doc """
  Broadcast that a file was added to a folder.
  """
  def broadcast_file_added(folder_id, file) do
    SecureSharingWeb.Endpoint.broadcast("folder:#{folder_id}", "file_added", %{
      id: file.id,
      encrypted_metadata: Base.encode64(file.encrypted_metadata || <<>>),
      blob_size: file.blob_size,
      status: file.status,
      created_at: file.created_at
    })
  end

  @doc """
  Broadcast that a file was removed from a folder.
  """
  def broadcast_file_removed(folder_id, file_id) do
    SecureSharingWeb.Endpoint.broadcast("folder:#{folder_id}", "file_removed", %{
      id: file_id
    })
  end

  @doc """
  Broadcast that a file was updated.
  """
  def broadcast_file_updated(folder_id, file) do
    SecureSharingWeb.Endpoint.broadcast("folder:#{folder_id}", "file_updated", %{
      id: file.id,
      encrypted_metadata: Base.encode64(file.encrypted_metadata || <<>>),
      blob_size: file.blob_size,
      status: file.status
    })
  end

  @doc """
  Broadcast that a subfolder was added.
  """
  def broadcast_folder_added(parent_id, folder) do
    SecureSharingWeb.Endpoint.broadcast("folder:#{parent_id}", "folder_added", %{
      id: folder.id,
      encrypted_metadata: Base.encode64(folder.encrypted_metadata || <<>>)
    })
  end

  @doc """
  Broadcast that a subfolder was removed.
  """
  def broadcast_folder_removed(parent_id, folder_id) do
    SecureSharingWeb.Endpoint.broadcast("folder:#{parent_id}", "folder_removed", %{
      id: folder_id
    })
  end
end
