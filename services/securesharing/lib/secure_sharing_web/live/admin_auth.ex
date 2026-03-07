defmodule SecureSharingWeb.AdminAuth do
  @moduledoc """
  LiveView on_mount hook for admin authentication.

  This hook verifies that the user is authenticated as an admin
  and assigns the current user to the socket.
  """
  use SecureSharingWeb, :verified_routes

  import Phoenix.Component

  alias SecureSharing.Accounts

  def on_mount(:default, _params, session, socket) do
    admin_user_id = session["admin_user_id"]

    if admin_user_id do
      case Accounts.get_user(admin_user_id) do
        nil ->
          {:halt, redirect_to_login(socket)}

        user ->
          if user.is_admin do
            {:cont, assign(socket, :current_user, user)}
          else
            {:halt,
             redirect_to_login(socket, "You are not authorized to access the admin panel.")}
          end
      end
    else
      {:halt, redirect_to_login(socket)}
    end
  end

  defp redirect_to_login(socket, message \\ "Please log in to access the admin panel.") do
    socket
    |> Phoenix.LiveView.put_flash(:error, message)
    |> Phoenix.LiveView.redirect(to: ~p"/admin/login")
  end
end
