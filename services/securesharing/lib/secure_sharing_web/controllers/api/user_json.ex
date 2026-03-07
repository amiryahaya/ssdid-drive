defmodule SecureSharingWeb.API.UserJSON do
  @moduledoc """
  JSON rendering for user responses.
  """

  alias SecureSharing.Accounts.User

  @doc """
  Renders a list of users.
  """
  def index(%{users: users}) do
    %{data: Enum.map(users, &user_summary/1)}
  end

  @doc """
  Renders a single user.
  """
  def show(%{user: user}) do
    %{data: user_data(user)}
  end

  @doc """
  Renders a user's key bundle.
  """
  def key_bundle(%{bundle: bundle}) do
    %{
      data: %{
        encrypted_master_key: encode_binary(bundle.encrypted_master_key),
        encrypted_private_keys: encode_binary(bundle.encrypted_private_keys),
        key_derivation_salt: encode_binary(bundle.key_derivation_salt),
        public_keys: bundle.public_keys
      }
    }
  end

  @doc """
  Renders a user's public keys (for sharing).
  """
  def public_key(%{user: user}) do
    %{
      data: %{
        id: user.id,
        email: user.email,
        public_keys: user.public_keys
      }
    }
  end

  # Full user data for authenticated user
  defp user_data(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      tenant_id: user.tenant_id,
      status: user.status,
      recovery_setup_complete: user.recovery_setup_complete,
      confirmed_at: user.confirmed_at,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  # Summary data for user listings
  defp user_summary(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      status: user.status
    }
  end

  defp encode_binary(nil), do: nil
  defp encode_binary(data) when is_binary(data), do: Base.encode64(data)
end
