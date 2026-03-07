defmodule SecureSharingWeb.Plugs.Authenticate do
  @moduledoc """
  Plug to authenticate requests using SSDID session tokens.

  Extracts the session token from the Authorization header, verifies it
  against the SSDID session store, resolves the DID to a user, and assigns
  the current user and tenant to the connection.

  ## Usage

      plug SecureSharingWeb.Plugs.Authenticate

  On success, assigns:
  - `current_user` - The authenticated User struct
  - `current_tenant` - The user's active Tenant struct
  - `current_did` - The user's DID string

  On failure, halts with 401 Unauthorized.
  """

  import Plug.Conn
  alias SecureSharing.Accounts

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ctx = SecureSharing.Ssdid.context()

    with {:ok, token} <- extract_token(conn),
         {:ok, did} <- verify_session(ctx, token),
         {:ok, user} <- load_user_by_did(did),
         {:ok, tenant} <- load_default_tenant(user) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant, tenant)
      |> assign(:current_did, did)
      |> assign(:user_id, user.id)
      |> assign(:tenant_id, tenant.id)
      |> assign(:role, get_role(user, tenant))
      |> assign(:session_token, token)
    else
      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.put_view(json: SecureSharingWeb.ErrorJSON)
        |> Phoenix.Controller.render("401.json")
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      ["bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp verify_session(ctx, token) do
    ctx.session_store_mod.get_session(ctx.session_store_name, token)
  end

  defp load_user_by_did(did) do
    case Accounts.get_user_by_did(did) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp load_default_tenant(user) do
    case Accounts.get_default_tenant(user) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, tenant}
    end
  end

  defp get_role(user, tenant) do
    case Accounts.get_user_tenant(user.id, tenant.id) do
      nil -> :member
      ut -> ut.role
    end
  end
end
