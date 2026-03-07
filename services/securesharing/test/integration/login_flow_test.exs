defmodule SecureSharing.Integration.LoginFlowTest do
  @moduledoc """
  End-to-end integration test for the login flow.
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  @factory_password "valid_password123"

  test "user logs in and receives access token", %{conn: conn} do
    tenant = insert(:tenant, slug: "login-test-#{System.unique_integer([:positive])}")
    user = insert(:user, tenant_id: tenant.id)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/login", %{
        "tenant_slug" => tenant.slug,
        "email" => user.email,
        "password" => @factory_password
      })

    assert %{"data" => %{"access_token" => token, "user" => user_data}} =
             json_response(conn, 200)

    assert is_binary(token)
    assert user_data["id"] == user.id
  end
end
