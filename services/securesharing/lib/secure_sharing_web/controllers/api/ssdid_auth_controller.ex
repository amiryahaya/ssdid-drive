defmodule SecureSharingWeb.API.SsdidAuthController do
  @moduledoc """
  SSDID authentication controller.

  Implements the full SSDID mutual authentication flow:
  1. Register: Client presents DID → server returns challenge + server signature
  2. Verify: Client returns signed challenge → server issues VC credential
  3. Authenticate: Client presents VC → server creates session
  4. Logout: Invalidate session token

  All authentication is DID-based. No email/password.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts
  alias SecureSharing.Audit
  alias SsdidServer.Api, as: SsdidApi

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  Initiate SSDID registration (mutual authentication step 1).

  POST /api/auth/ssdid/register

  Request:
  ```json
  {
    "did": "did:ssdid:abc123",
    "key_id": "did:ssdid:abc123#key-1"
  }
  ```

  Response:
  ```json
  {
    "challenge": "base64url-random",
    "server_did": "did:ssdid:server",
    "server_key_id": "did:ssdid:server#key-1",
    "server_signature": "ubase64url-signature"
  }
  ```
  """
  def register(conn, %{"did" => client_did, "key_id" => client_key_id}) do
    case SsdidApi.handle_register(client_did, client_key_id) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> render(:register, result: result)

      {:error, :did_not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:unprocessable_entity, inspect(reason)}}
    end
  end

  @doc """
  Complete SSDID registration (mutual authentication step 2).

  POST /api/auth/ssdid/register/verify

  Request:
  ```json
  {
    "did": "did:ssdid:abc123",
    "key_id": "did:ssdid:abc123#key-1",
    "signed_challenge": "ubase64url-signature"
  }
  ```

  Response:
  ```json
  {
    "credential": { ... },
    "did": "did:ssdid:abc123"
  }
  ```
  """
  def verify(conn, %{"did" => did, "key_id" => key_id, "signed_challenge" => signed}) do
    case SsdidApi.handle_verify_response(did, key_id, signed) do
      {:ok, %{"credential" => credential} = result} ->
        # Auto-provision user account on first registration
        ensure_user_exists(did)

        Audit.log_success(conn, "ssdid.register", "did", did)

        conn
        |> put_status(:created)
        |> render(:verify, result: result)

      {:error, reason} ->
        Audit.log_failure(conn, "ssdid.register", "did", did, %{}, inspect(reason))
        {:error, {:unauthorized, "Registration verification failed"}}
    end
  end

  @doc """
  Authenticate with SSDID credential.

  POST /api/auth/ssdid/authenticate

  Request:
  ```json
  {
    "credential": { ... }
  }
  ```

  Response:
  ```json
  {
    "session_token": "base64url-token",
    "did": "did:ssdid:abc123",
    "server_did": "did:ssdid:server",
    "server_signature": "ubase64url-signature",
    "user": { ... },
    "tenants": [ ... ]
  }
  ```
  """
  def authenticate(conn, %{"credential" => credential}) do
    case SsdidApi.handle_authenticate(credential) do
      {:ok, %{"session_token" => session_token, "did" => did} = result} ->
        case Accounts.get_user_by_did(did) do
          nil ->
            {:error, {:not_found, "No account linked to this DID"}}

          user ->
            # Record login activity
            Accounts.record_login(user)
            user_tenants = Accounts.get_user_tenants(user.id)

            Audit.log_success(conn, "ssdid.authenticate", "did", did)

            conn
            |> put_status(:ok)
            |> render(:authenticate,
              result: result,
              user: user,
              tenants: user_tenants
            )
        end

      {:error, reason} ->
        Audit.log_failure(conn, "ssdid.authenticate", "did", nil, %{}, inspect(reason))
        {:error, {:unauthorized, "Authentication failed"}}
    end
  end

  @doc """
  Switch active tenant.

  POST /api/auth/ssdid/tenant/switch

  Request:
  ```json
  {
    "tenant_id": "uuid"
  }
  ```
  """
  def switch_tenant(conn, %{"tenant_id" => tenant_id}) do
    user = conn.assigns.current_user

    case Accounts.get_user_tenant(user.id, tenant_id) do
      nil ->
        {:error, {:forbidden, "Not a member of this tenant"}}

      user_tenant ->
        tenant = Accounts.get_tenant(tenant_id)

        conn
        |> put_status(:ok)
        |> render(:tenant_switch, tenant: tenant, role: user_tenant.role)
    end
  end

  @doc """
  Logout — invalidate SSDID session.

  POST /api/auth/ssdid/logout
  """
  def logout(conn, _params) do
    token = conn.assigns[:session_token]
    ctx = SecureSharing.Ssdid.context()

    if token do
      ctx.session_store_mod.delete_session(ctx.session_store_name, token)
    end

    Audit.log_success(conn, "ssdid.logout", "did", conn.assigns[:current_did])

    send_resp(conn, :no_content, "")
  end

  @doc """
  Get server identity info for client discovery.

  GET /api/auth/ssdid/server-info
  """
  def server_info(conn, _params) do
    ctx = SecureSharing.Ssdid.context()

    conn
    |> put_status(:ok)
    |> json(%{
      server_did: ctx.identity.did,
      server_key_id: ctx.identity.key_id,
      service_name: ctx.service_name,
      registry_url: Application.get_env(:secure_sharing, :ssdid_registry_url, "https://registry.ssdid.my")
    })
  end

  # Auto-provision a user account for a new DID
  defp ensure_user_exists(did) do
    case Accounts.get_user_by_did(did) do
      nil ->
        Accounts.create_user_from_did(did)

      _user ->
        :ok
    end
  end
end
