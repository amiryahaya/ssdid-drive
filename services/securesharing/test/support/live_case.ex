defmodule SecureSharingWeb.LiveCase do
  @moduledoc """
  This module defines the test case to be used by LiveView tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import SecureSharingWeb.LiveCase
      import SecureSharing.Factory

      # The default endpoint for testing
      @endpoint SecureSharingWeb.Endpoint

      # Helpers
      use SecureSharingWeb, :verified_routes
    end
  end

  setup tags do
    SecureSharing.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Sets up an admin user session for the connection.
  """
  def login_admin(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:admin_user_id, user.id)
  end
end
