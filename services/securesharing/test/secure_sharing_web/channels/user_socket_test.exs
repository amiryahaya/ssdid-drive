defmodule SecureSharingWeb.UserSocketTest do
  use SecureSharingWeb.ChannelCase, async: true

  alias SecureSharingWeb.UserSocket
  alias SecureSharingWeb.Auth.Token

  defp socket_connect(params) do
    Phoenix.ChannelTest.__connect__(
      SecureSharingWeb.Endpoint,
      SecureSharingWeb.UserSocket,
      params,
      []
    )
  end

  describe "connect/3" do
    test "connects with valid access token" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      {:ok, token} = Token.generate_access_token(user)

      assert {:ok, socket} = socket_connect(%{"token" => token})
      assert socket.assigns.user_id == user.id
      assert socket.assigns.tenant_id == user.tenant_id
      assert socket.assigns.current_user.id == user.id
    end

    test "rejects connection with invalid token" do
      assert :error = socket_connect(%{"token" => "invalid_token"})
    end

    test "rejects connection with expired token" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      # Create an expired token manually
      claims = %{
        "user_id" => user.id,
        "tenant_id" => user.tenant_id,
        "type" => "access",
        "iss" => "secure_sharing",
        "iat" => DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix(),
        "exp" => DateTime.utc_now() |> DateTime.add(-1800) |> DateTime.to_unix()
      }

      secret =
        Application.get_env(:secure_sharing, :jwt_secret) ||
          "dev_secret_key_change_in_production_minimum_32_bytes"

      signer = Joken.Signer.create("HS256", secret)
      {:ok, expired_token, _} = Joken.encode_and_sign(claims, signer)

      assert :error = socket_connect(%{"token" => expired_token})
    end

    test "rejects connection with refresh token (wrong type)" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      {:ok, refresh_token} = Token.generate_refresh_token(user)

      assert :error = socket_connect(%{"token" => refresh_token})
    end

    test "rejects connection without token" do
      assert :error = socket_connect(%{})
    end

    test "rejects connection for non-existent user" do
      # Create a token with a fake user_id
      claims = %{
        "user_id" => Ecto.UUID.generate(),
        "tenant_id" => Ecto.UUID.generate(),
        "type" => "access",
        "iss" => "secure_sharing",
        "iat" => DateTime.utc_now() |> DateTime.to_unix(),
        "exp" => DateTime.utc_now() |> DateTime.add(900) |> DateTime.to_unix()
      }

      secret =
        Application.get_env(:secure_sharing, :jwt_secret) ||
          "dev_secret_key_change_in_production_minimum_32_bytes"

      signer = Joken.Signer.create("HS256", secret)
      {:ok, token, _} = Joken.encode_and_sign(claims, signer)

      assert :error = socket_connect(%{"token" => token})
    end
  end

  describe "id/1" do
    test "returns user-specific socket id" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      socket = authenticated_socket(user)

      assert UserSocket.id(socket) == "user_socket:#{user.id}"
    end
  end
end
