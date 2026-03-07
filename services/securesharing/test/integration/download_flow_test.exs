defmodule SecureSharing.Integration.DownloadFlowTest do
  @moduledoc """
  End-to-end integration test for the download flow.
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  @factory_password "valid_password123"

  test "user requests a download URL for a completed file", %{conn: conn} do
    tenant = insert(:tenant, slug: "download-test-#{System.unique_integer([:positive])}")
    user = insert(:user, tenant_id: tenant.id)
    root_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)

    file =
      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: root_folder.id,
        status: "complete"
      )

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/login", %{
        "tenant_slug" => tenant.slug,
        "email" => user.email,
        "password" => @factory_password
      })

    %{"data" => %{"access_token" => token}} = json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/files/#{file.id}/download-url")

    assert %{"data" => %{"download_url" => download_url}} = json_response(conn, 200)
    assert is_binary(download_url)
  end
end
