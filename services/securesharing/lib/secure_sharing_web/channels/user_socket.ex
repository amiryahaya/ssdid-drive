defmodule SecureSharingWeb.UserSocket do
  @moduledoc """
  WebSocket for authenticated user connections.

  Authenticates users via JWT token passed in connection params.
  """

  use Phoenix.Socket

  alias SecureSharing.Accounts
  alias SecureSharingWeb.Auth.Token

  # Channels
  channel "folder:*", SecureSharingWeb.FolderChannel
  channel "notification:*", SecureSharingWeb.NotificationChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Token.verify_access_token(token) do
      {:ok, claims} ->
        user_id = claims["user_id"]
        tenant_id = claims["tenant_id"]

        case Accounts.get_user(user_id) do
          nil ->
            :error

          user ->
            # Compare as strings to handle UUID format differences
            if to_string(user.tenant_id) == to_string(tenant_id) do
              socket =
                socket
                |> assign(:current_user, user)
                |> assign(:user_id, user_id)
                |> assign(:tenant_id, user.tenant_id)

              {:ok, socket}
            else
              :error
            end
        end

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
