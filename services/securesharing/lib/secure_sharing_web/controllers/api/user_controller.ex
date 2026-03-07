defmodule SecureSharingWeb.API.UserController do
  @moduledoc """
  Controller for user profile and key management.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  Get current user profile.

  GET /api/me
  """
  def show(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :show, user: user)
  end

  @doc """
  Get current user's encrypted key bundle.

  GET /api/me/keys

  Returns the encrypted key material for client-side decryption.
  """
  def key_bundle(conn, _params) do
    user = conn.assigns.current_user
    {:ok, bundle} = Accounts.get_key_bundle(user)
    render(conn, :key_bundle, bundle: bundle)
  end

  @doc """
  Update current user's profile.

  PUT /api/me

  Request body:
  ```json
  {
    "display_name": "John Doe"
  }
  ```
  """
  def update(conn, params) do
    user = conn.assigns.current_user

    attrs =
      %{}
      |> maybe_put(:display_name, params["display_name"])

    with {:ok, updated_user} <- Accounts.update_user_profile(user, attrs) do
      render(conn, :show, user: updated_user)
    end
  end

  @doc """
  Update current user's key material.

  PUT /api/me/keys

  Used after password change or recovery to update encrypted keys.

  Request body:
  ```json
  {
    "encrypted_private_keys": "base64...",
    "encrypted_master_key": "base64...",
    "key_derivation_salt": "base64...",
    "public_keys": {"kem": "base64...", "sign": "base64..."}
  }
  ```
  """
  def update_keys(conn, params) do
    user = conn.assigns.current_user
    attrs = decode_key_params(params)

    with {:ok, updated_user} <- Accounts.update_key_material(user, attrs) do
      render(conn, :show, user: updated_user)
    end
  end

  @doc """
  List users in the current tenant.

  GET /api/users

  Returns basic info for all users in the tenant (for sharing UI).
  """
  def index(conn, _params) do
    tenant_id = conn.assigns.current_tenant.id
    users = Accounts.list_users(tenant_id)
    render(conn, :index, users: users)
  end

  @doc """
  Get a user's public keys.

  GET /api/users/:id/public-key

  Returns the public keys for encrypting shares to this user.
  """
  def public_key(conn, %{"id" => id}) do
    current_user = conn.assigns.current_user

    with {:ok, user} <- get_user(id),
         :ok <- verify_same_tenant(current_user, user) do
      render(conn, :public_key, user: user)
    end
  end

  # Private functions

  defp get_user(id) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp verify_same_tenant(current_user, target_user) do
    if current_user.tenant_id == target_user.tenant_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp decode_key_params(params) do
    %{}
    |> maybe_put(:encrypted_private_keys, decode_binary(params["encrypted_private_keys"]))
    |> maybe_put(:encrypted_master_key, decode_binary(params["encrypted_master_key"]))
    |> maybe_put(:key_derivation_salt, decode_binary(params["key_derivation_salt"]))
    |> maybe_put(:public_keys, params["public_keys"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64_optional(data)
  end
end
