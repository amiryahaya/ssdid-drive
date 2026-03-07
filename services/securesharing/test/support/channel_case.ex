defmodule SecureSharingWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SecureSharingWeb.ChannelCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import SecureSharingWeb.ChannelCase
      import SecureSharing.Factory

      # The default endpoint for testing
      @endpoint SecureSharingWeb.Endpoint
    end
  end

  setup tags do
    SecureSharing.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Helper to create an authenticated socket for a user.
  """
  def authenticated_socket(user) do
    {:ok, token} = SecureSharingWeb.Auth.Token.generate_access_token(user)

    {:ok, socket} =
      Phoenix.ChannelTest.__connect__(
        SecureSharingWeb.Endpoint,
        SecureSharingWeb.UserSocket,
        %{"token" => token},
        []
      )

    socket
  end
end
