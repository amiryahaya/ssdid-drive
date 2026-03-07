defmodule SecureSharingWeb.Controllers.Api.ProviderControllerTest do
  @moduledoc """
  Tests for auth provider and credential management API endpoints.
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  setup do
    tenant = insert(:tenant)
    user = insert(:user, tenant_id: tenant.id)
    insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

    idp_config = insert(:idp_config, tenant_id: tenant.id)
    oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)

    {:ok, tenant: tenant, user: user, idp_config: idp_config, oidc_config: oidc_config}
  end

  # ============================================================================
  # GET /api/auth/providers
  # ============================================================================

  describe "GET /api/auth/providers" do
    test "lists enabled providers for a tenant", %{conn: conn, tenant: tenant} do
      conn = get(conn, ~p"/api/auth/providers", %{"tenant_slug" => tenant.slug})

      response = json_response(conn, 200)
      providers = response["data"]

      assert is_list(providers)
      assert length(providers) >= 2

      types = Enum.map(providers, & &1["type"])
      assert "webauthn" in types
      assert "oidc" in types
    end

    test "returns provider config without secrets", %{conn: conn, tenant: tenant} do
      conn = get(conn, ~p"/api/auth/providers", %{"tenant_slug" => tenant.slug})

      response = json_response(conn, 200)
      providers = response["data"]

      oidc_provider = Enum.find(providers, fn p -> p["type"] == "oidc" end)
      assert oidc_provider["config"]["client_id"]
      refute Map.has_key?(oidc_provider["config"], "client_secret")
    end

    test "returns error for unknown tenant", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/providers", %{"tenant_slug" => "nonexistent"})

      assert json_response(conn, 404)
    end

    test "returns error when no tenant specified", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/providers", %{})

      assert json_response(conn, 404)
    end
  end

  # ============================================================================
  # GET /api/auth/credentials
  # ============================================================================

  describe "GET /api/auth/credentials" do
    test "lists user's credentials", %{
      conn: conn,
      user: user,
      tenant: tenant,
      idp_config: idp_config
    } do
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/auth/credentials")

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      cred = Enum.at(response["data"], 0)
      assert cred["type"] == "webauthn"
      assert cred["device_name"]
    end

    test "filters by type", %{
      conn: conn,
      user: user,
      tenant: tenant,
      idp_config: idp_config,
      oidc_config: oidc_config
    } do
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      insert(:oidc_credential, user_id: user.id, provider_id: oidc_config.id)

      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/auth/credentials", %{"type" => "webauthn"})

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert Enum.at(response["data"], 0)["type"] == "webauthn"
    end

    test "returns empty list when no credentials", %{conn: conn, user: user, tenant: tenant} do
      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/auth/credentials")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "returns 401 without auth", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/credentials")
      assert json_response(conn, 401)
    end
  end

  # ============================================================================
  # PUT /api/auth/credentials/:id
  # ============================================================================

  describe "PUT /api/auth/credentials/:id" do
    test "renames a credential", %{
      conn: conn,
      user: user,
      tenant: tenant,
      idp_config: idp_config
    } do
      cred = insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      conn =
        conn
        |> authenticate(user, tenant)
        |> put(~p"/api/auth/credentials/#{cred.id}", %{"device_name" => "Renamed Passkey"})

      response = json_response(conn, 200)
      assert response["data"]["device_name"] == "Renamed Passkey"
    end

    test "returns 404 for non-existent credential", %{conn: conn, user: user, tenant: tenant} do
      conn =
        conn
        |> authenticate(user, tenant)
        |> put(~p"/api/auth/credentials/#{Ecto.UUID.generate()}", %{
          "device_name" => "Test"
        })

      assert json_response(conn, 404)
    end

    test "returns 403 for other user's credential", %{
      conn: conn,
      tenant: tenant,
      idp_config: idp_config
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id)
      cred = insert(:webauthn_credential, user_id: other_user.id, provider_id: idp_config.id)

      user2 = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user2.id, tenant_id: tenant.id)

      conn =
        conn
        |> authenticate(user2, tenant)
        |> put(~p"/api/auth/credentials/#{cred.id}", %{"device_name" => "Stolen"})

      assert json_response(conn, 403)
    end
  end

  # ============================================================================
  # DELETE /api/auth/credentials/:id
  # ============================================================================

  describe "DELETE /api/auth/credentials/:id" do
    test "deletes a credential when user has multiple", %{
      conn: conn,
      user: user,
      tenant: tenant,
      idp_config: idp_config
    } do
      cred1 = insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      _cred2 = insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      conn =
        conn
        |> authenticate(user, tenant)
        |> delete(~p"/api/auth/credentials/#{cred1.id}")

      assert response(conn, 204)
    end

    test "prevents deleting last credential", %{
      conn: conn,
      user: user,
      tenant: tenant,
      idp_config: idp_config
    } do
      cred = insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      conn =
        conn
        |> authenticate(user, tenant)
        |> delete(~p"/api/auth/credentials/#{cred.id}")

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "last credential"
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
