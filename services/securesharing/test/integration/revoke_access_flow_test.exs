defmodule SecureSharing.Integration.RevokeAccessFlowTest do
  @moduledoc """
  End-to-end integration test for revoking access to a shared file.
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  @factory_password "valid_password123"

  test "grantor revokes a file share and grantee loses access", %{conn: conn} do
    tenant = insert(:tenant, slug: "revoke-test-#{System.unique_integer([:positive])}")
    grantor = insert(:user, tenant_id: tenant.id)
    grantee = insert(:user, tenant_id: tenant.id)
    root_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: grantor.id)
    file = insert(:file, tenant_id: tenant.id, owner_id: grantor.id, folder_id: root_folder.id)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/login", %{
        "tenant_slug" => tenant.slug,
        "email" => grantor.email,
        "password" => @factory_password
      })

    %{"data" => %{"access_token" => grantor_token}} = json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/login", %{
        "tenant_slug" => tenant.slug,
        "email" => grantee.email,
        "password" => @factory_password
      })

    %{"data" => %{"access_token" => grantee_token}} = json_response(conn, 200)

    share_attrs = %{
      "grantee_id" => grantee.id,
      "file_id" => file.id,
      "permission" => "read",
      "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
    }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{grantor_token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/shares/file", share_attrs)

    assert %{"data" => %{"id" => share_id}} = json_response(conn, 201)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{grantee_token}")
      |> get(~p"/api/files/#{file.id}")

    assert %{"data" => %{"id" => file_id}} = json_response(conn, 200)
    assert file_id == file.id

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{grantor_token}")
      |> delete(~p"/api/shares/#{share_id}")

    assert response(conn, 204)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{grantee_token}")
      |> get(~p"/api/files/#{file.id}")

    assert json_response(conn, 403)
  end
end
