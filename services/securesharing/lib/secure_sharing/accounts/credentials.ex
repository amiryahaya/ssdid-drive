defmodule SecureSharing.Accounts.Credentials do
  @moduledoc """
  Sub-module for managing authentication credentials (WebAuthn, OIDC, etc.)
  and IdP configurations.
  """

  import Ecto.Query
  alias SecureSharing.Repo
  alias SecureSharing.Accounts.{Credential, IdpConfig}

  # ============================================================================
  # WebAuthn Credentials
  # ============================================================================

  @doc """
  Creates a WebAuthn credential.
  """
  def create_webauthn_credential(attrs) do
    %Credential{}
    |> Credential.webauthn_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a credential by its WebAuthn credential_id (binary).
  """
  def get_credential_by_credential_id(credential_id) when is_binary(credential_id) do
    Credential
    |> where([c], c.credential_id == ^credential_id and c.type == :webauthn)
    |> Repo.one()
    |> Repo.preload([:user, :provider])
  end

  @doc """
  Gets all WebAuthn credentials for a user.
  """
  def get_user_webauthn_credentials(user_id) do
    Credential
    |> where([c], c.user_id == ^user_id and c.type == :webauthn)
    |> order_by([c], desc: c.created_at)
    |> Repo.all()
  end

  @doc """
  Updates a credential's sign counter after successful authentication.
  """
  def update_credential_counter(%Credential{} = credential, new_counter) do
    credential
    |> Credential.counter_changeset(%{counter: new_counter})
    |> Repo.update()
  end

  @doc """
  Updates the last_used_at timestamp on a credential.
  """
  def touch_credential(%Credential{} = credential) do
    credential
    |> Credential.touch_changeset()
    |> Repo.update()
  end

  # ============================================================================
  # OIDC Credentials
  # ============================================================================

  @doc """
  Creates an OIDC credential.
  """
  def create_oidc_credential(attrs) do
    %Credential{}
    |> Credential.external_changeset(attrs, :oidc)
    |> Repo.insert()
  end

  @doc """
  Looks up an OIDC credential by provider_id and external_id (sub claim).
  """
  def get_credential_by_external_id(provider_id, external_id) do
    Credential
    |> where(
      [c],
      c.provider_id == ^provider_id and c.external_id == ^external_id and c.type == :oidc
    )
    |> Repo.one()
    |> case do
      nil -> nil
      credential -> Repo.preload(credential, [:user, :provider])
    end
  end

  # ============================================================================
  # Generic Credential Operations
  # ============================================================================

  @doc """
  Lists all credentials for a user.
  """
  def list_user_credentials(user_id) do
    Credential
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.created_at)
    |> Repo.all()
  end

  @doc """
  Lists credentials of a specific type for a user.
  """
  def list_user_credentials(user_id, type) when is_atom(type) do
    Credential
    |> where([c], c.user_id == ^user_id and c.type == ^type)
    |> order_by([c], desc: c.created_at)
    |> Repo.all()
  end

  @doc """
  Gets a credential by ID.
  """
  def get_credential(id) do
    Repo.get(Credential, id)
  end

  @doc """
  Deletes a credential, ensuring it belongs to the user.
  """
  def delete_credential(id, user_id) do
    case Repo.get(Credential, id) do
      nil ->
        {:error, :not_found}

      %Credential{user_id: ^user_id} = credential ->
        Repo.delete(credential)

      _credential ->
        {:error, :forbidden}
    end
  end

  @doc """
  Updates a credential's device name.
  """
  def update_device_name(%Credential{} = credential, device_name) do
    credential
    |> Credential.device_name_changeset(%{device_name: device_name})
    |> Repo.update()
  end

  @doc """
  Counts the number of credentials for a user.
  """
  def count_user_credentials(user_id) do
    Credential
    |> where([c], c.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  # ============================================================================
  # IdP Configuration
  # ============================================================================

  @doc """
  Gets all enabled IdP configs for a tenant, ordered by priority.
  """
  def get_enabled_idp_configs(tenant_id) do
    IdpConfig
    |> where([i], i.tenant_id == ^tenant_id and i.enabled == true)
    |> order_by([i], asc: i.priority)
    |> Repo.all()
  end

  @doc """
  Gets an IdP config by ID.
  """
  def get_idp_config(id) do
    Repo.get(IdpConfig, id)
  end

  @doc """
  Gets the WebAuthn IdP config for a tenant.
  """
  def get_webauthn_config(tenant_id) do
    IdpConfig
    |> where([i], i.tenant_id == ^tenant_id and i.type == :webauthn and i.enabled == true)
    |> Repo.one()
  end

  @doc """
  Gets all OIDC IdP configs for a tenant.
  """
  def get_oidc_configs(tenant_id) do
    IdpConfig
    |> where([i], i.tenant_id == ^tenant_id and i.type == :oidc and i.enabled == true)
    |> order_by([i], asc: i.priority)
    |> Repo.all()
  end

  @doc """
  Creates an IdP configuration.
  """
  def create_idp_config(attrs) do
    %IdpConfig{}
    |> IdpConfig.changeset(attrs)
    |> Repo.insert()
  end
end
