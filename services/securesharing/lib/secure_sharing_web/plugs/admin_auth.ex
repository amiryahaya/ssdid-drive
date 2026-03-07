defmodule SecureSharingWeb.Plugs.AdminAuth do
  @moduledoc """
  Plug for authenticating admin users via session or token.

  This plug checks if the current user is an admin. If using session-based
  authentication, it reads from the session. If using token-based auth,
  it verifies the JWT and checks admin status.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias SecureSharingWeb.Auth.Token
  alias SecureSharing.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      # Check session first (for browser-based admin)
      user = get_session(conn, :current_user) ->
        verify_admin(conn, user)

      # Fall back to token auth
      token = get_token_from_header(conn) ->
        authenticate_with_token(conn, token)

      true ->
        unauthorized(conn)
    end
  end

  defp get_token_from_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp authenticate_with_token(conn, token) do
    case Token.verify_access_token(token) do
      {:ok, claims} ->
        user_id = claims["user_id"]

        case Accounts.get_user(user_id) do
          nil ->
            unauthorized(conn)

          user ->
            verify_admin(conn, user)
        end

      {:error, _reason} ->
        unauthorized(conn)
    end
  end

  defp verify_admin(conn, user) when is_map(user) do
    # Handle both structs and maps
    is_admin = Map.get(user, :is_admin) || Map.get(user, "is_admin")

    if is_admin do
      # Reload user to ensure fresh data
      user = if is_struct(user), do: user, else: Accounts.get_user(user.id || user["id"])

      conn
      |> assign(:current_user, user)
    else
      forbidden(conn)
    end
  end

  defp verify_admin(conn, _), do: unauthorized(conn)

  defp unauthorized(conn) do
    conn
    |> put_flash(:error, "You must be logged in to access this page.")
    |> redirect(to: "/admin/login")
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_flash(:error, "You must be an administrator to access this page.")
    |> redirect(to: "/")
    |> halt()
  end
end
