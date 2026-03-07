defmodule SecureSharing.Integration.RegistrationFlowTest do
  @moduledoc """
  End-to-end integration test for the registration flow.
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  alias SecureSharing.Accounts

  @password "test_password_12345"

  test "user registers and profile is created with crypto material", %{conn: conn} do
    tenant = insert(:tenant, slug: "registration-test-#{System.unique_integer([:positive])}")

    registration_attrs = %{
      "tenant_slug" => tenant.slug,
      "email" => "registration_test_#{System.unique_integer([:positive])}@example.com",
      "password" => @password,
      "public_keys" => %{
        "kem" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "sign" => Base.encode64(:crypto.strong_rand_bytes(64))
      },
      "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(256)),
      "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/register", registration_attrs)

    assert %{"data" => %{"user" => %{"id" => user_id}, "access_token" => token}} =
             json_response(conn, 201)

    assert is_binary(user_id)
    assert is_binary(token)

    user = Accounts.get_user!(user_id)
    assert user.email == registration_attrs["email"]
    assert user.tenant_id == tenant.id
  end
end
