defmodule SecureSharingWeb.Presence do
  @moduledoc """
  Tracks user presence in channels.

  Used to show who is currently viewing a folder or file.
  """

  use Phoenix.Presence,
    otp_app: :secure_sharing,
    pubsub_server: SecureSharing.PubSub

  @doc """
  Fetch presence list with user metadata.

  Returns a map of user_id => %{metas: [%{...}]}
  """
  def fetch(_topic, presences) do
    # Optionally enrich presence data with user info
    # For now, we just pass through the presences
    presences
  end

  @doc """
  Track a user in a folder channel.
  """
  def track_user(socket, folder_id) do
    track(socket, socket.assigns.user_id, %{
      folder_id: folder_id,
      online_at: System.system_time(:second),
      user_id: socket.assigns.user_id
    })
  end

  @doc """
  List users currently viewing a folder.
  """
  def list_folder_users(folder_id) do
    list("folder:#{folder_id}")
  end
end
