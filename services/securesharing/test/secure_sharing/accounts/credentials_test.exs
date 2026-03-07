defmodule SecureSharing.Accounts.CredentialsTest do
  use SecureSharing.DataCase, async: true

  import SecureSharing.Factory

  alias SecureSharing.Accounts.Credentials

  setup do
    tenant = insert(:tenant)
    user = insert(:user, tenant_id: tenant.id)
    insert(:user_tenant, user_id: user.id, tenant_id: tenant.id)
    idp_config = insert(:idp_config, tenant_id: tenant.id)

    {:ok, tenant: tenant, user: user, idp_config: idp_config}
  end

  # ============================================================================
  # WebAuthn Credentials
  # ============================================================================

  describe "create_webauthn_credential/1" do
    test "creates a webauthn credential", %{user: user, idp_config: idp_config} do
      attrs = %{
        user_id: user.id,
        provider_id: idp_config.id,
        credential_id: :crypto.strong_rand_bytes(64),
        public_key: :crypto.strong_rand_bytes(77),
        counter: 0,
        device_name: "My MacBook"
      }

      assert {:ok, cred} = Credentials.create_webauthn_credential(attrs)
      assert cred.type == :webauthn
      assert cred.device_name == "My MacBook"
      assert cred.counter == 0
    end

    test "fails without required fields" do
      assert {:error, changeset} = Credentials.create_webauthn_credential(%{})
      assert errors_on(changeset)[:user_id]
      assert errors_on(changeset)[:credential_id]
    end
  end

  describe "get_credential_by_credential_id/1" do
    test "finds credential by binary ID", %{user: user, idp_config: idp_config} do
      cred_id = :crypto.strong_rand_bytes(64)

      {:ok, _cred} =
        Credentials.create_webauthn_credential(%{
          user_id: user.id,
          provider_id: idp_config.id,
          credential_id: cred_id,
          public_key: :crypto.strong_rand_bytes(77)
        })

      result = Credentials.get_credential_by_credential_id(cred_id)
      assert result != nil
      assert result.credential_id == cred_id
      assert result.user != nil
    end

    test "returns nil for non-existent ID" do
      assert Credentials.get_credential_by_credential_id(:crypto.strong_rand_bytes(64)) == nil
    end
  end

  describe "get_user_webauthn_credentials/1" do
    test "returns user's webauthn credentials", %{user: user, idp_config: idp_config} do
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      creds = Credentials.get_user_webauthn_credentials(user.id)
      assert length(creds) == 2
    end

    test "returns empty list for user without credentials", %{tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      assert Credentials.get_user_webauthn_credentials(other_user.id) == []
    end
  end

  describe "update_credential_counter/2" do
    test "updates the counter", %{user: user, idp_config: idp_config} do
      {:ok, cred} =
        Credentials.create_webauthn_credential(%{
          user_id: user.id,
          provider_id: idp_config.id,
          credential_id: :crypto.strong_rand_bytes(64),
          public_key: :crypto.strong_rand_bytes(77),
          counter: 0
        })

      assert {:ok, updated} = Credentials.update_credential_counter(cred, 5)
      assert updated.counter == 5
    end
  end

  describe "touch_credential/1" do
    test "updates last_used_at", %{user: user, idp_config: idp_config} do
      {:ok, cred} =
        Credentials.create_webauthn_credential(%{
          user_id: user.id,
          provider_id: idp_config.id,
          credential_id: :crypto.strong_rand_bytes(64),
          public_key: :crypto.strong_rand_bytes(77)
        })

      assert cred.last_used_at == nil
      assert {:ok, touched} = Credentials.touch_credential(cred)
      assert touched.last_used_at != nil
    end
  end

  # ============================================================================
  # OIDC Credentials
  # ============================================================================

  describe "create_oidc_credential/1" do
    test "creates an OIDC credential", %{user: user, tenant: tenant} do
      oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)

      attrs = %{
        user_id: user.id,
        provider_id: oidc_config.id,
        external_id: "google-sub-12345",
        device_name: "Google Account"
      }

      assert {:ok, cred} = Credentials.create_oidc_credential(attrs)
      assert cred.type == :oidc
      assert cred.external_id == "google-sub-12345"
    end
  end

  describe "get_credential_by_external_id/2" do
    test "finds OIDC credential", %{user: user, tenant: tenant} do
      oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)

      {:ok, _cred} =
        Credentials.create_oidc_credential(%{
          user_id: user.id,
          provider_id: oidc_config.id,
          external_id: "sub-abc"
        })

      result = Credentials.get_credential_by_external_id(oidc_config.id, "sub-abc")
      assert result != nil
      assert result.external_id == "sub-abc"
    end

    test "returns nil for non-existent external_id", %{tenant: tenant} do
      oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)
      assert Credentials.get_credential_by_external_id(oidc_config.id, "nonexistent") == nil
    end
  end

  # ============================================================================
  # Generic Operations
  # ============================================================================

  describe "list_user_credentials/1" do
    test "lists all types", %{user: user, tenant: tenant, idp_config: idp_config} do
      oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      insert(:oidc_credential, user_id: user.id, provider_id: oidc_config.id)

      creds = Credentials.list_user_credentials(user.id)
      assert length(creds) == 2
    end
  end

  describe "list_user_credentials/2" do
    test "filters by type", %{user: user, tenant: tenant, idp_config: idp_config} do
      oidc_config = insert(:oidc_idp_config, tenant_id: tenant.id)
      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      insert(:oidc_credential, user_id: user.id, provider_id: oidc_config.id)

      webauthn_creds = Credentials.list_user_credentials(user.id, :webauthn)
      assert length(webauthn_creds) == 1
      assert Enum.at(webauthn_creds, 0).type == :webauthn

      oidc_creds = Credentials.list_user_credentials(user.id, :oidc)
      assert length(oidc_creds) == 1
    end
  end

  describe "delete_credential/2" do
    test "deletes user's own credential", %{user: user, idp_config: idp_config} do
      {:ok, cred} =
        Credentials.create_webauthn_credential(%{
          user_id: user.id,
          provider_id: idp_config.id,
          credential_id: :crypto.strong_rand_bytes(64),
          public_key: :crypto.strong_rand_bytes(77)
        })

      assert {:ok, _} = Credentials.delete_credential(cred.id, user.id)
      assert Credentials.get_credential(cred.id) == nil
    end

    test "returns forbidden for other user's credential", %{
      user: user,
      tenant: tenant,
      idp_config: idp_config
    } do
      other_user = insert(:user, tenant_id: tenant.id)

      {:ok, cred} =
        Credentials.create_webauthn_credential(%{
          user_id: user.id,
          provider_id: idp_config.id,
          credential_id: :crypto.strong_rand_bytes(64),
          public_key: :crypto.strong_rand_bytes(77)
        })

      assert {:error, :forbidden} = Credentials.delete_credential(cred.id, other_user.id)
    end

    test "returns not_found for non-existent credential", %{user: user} do
      assert {:error, :not_found} =
               Credentials.delete_credential(Ecto.UUID.generate(), user.id)
    end
  end

  describe "update_device_name/2" do
    test "updates device name", %{user: user, idp_config: idp_config} do
      cred = insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)

      assert {:ok, updated} = Credentials.update_device_name(cred, "New Name")
      assert updated.device_name == "New Name"
    end
  end

  describe "count_user_credentials/1" do
    test "counts credentials", %{user: user, idp_config: idp_config} do
      assert Credentials.count_user_credentials(user.id) == 0

      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      assert Credentials.count_user_credentials(user.id) == 1

      insert(:webauthn_credential, user_id: user.id, provider_id: idp_config.id)
      assert Credentials.count_user_credentials(user.id) == 2
    end
  end

  # ============================================================================
  # IdP Config
  # ============================================================================

  describe "get_enabled_idp_configs/1" do
    test "returns enabled configs ordered by priority", %{tenant: tenant, idp_config: _} do
      insert(:oidc_idp_config, tenant_id: tenant.id, priority: 20)
      insert(:oidc_idp_config, tenant_id: tenant.id, priority: 5)

      configs = Credentials.get_enabled_idp_configs(tenant.id)
      # Should include the webauthn config from setup + 2 oidc configs
      assert length(configs) >= 3
      priorities = Enum.map(configs, & &1.priority)
      assert priorities == Enum.sort(priorities)
    end

    test "excludes disabled configs", %{tenant: tenant} do
      insert(:oidc_idp_config, tenant_id: tenant.id, enabled: false)

      configs = Credentials.get_enabled_idp_configs(tenant.id)
      assert Enum.all?(configs, fn c -> c.enabled end)
    end
  end

  describe "get_webauthn_config/1" do
    test "returns webauthn config for tenant", %{tenant: tenant} do
      config = Credentials.get_webauthn_config(tenant.id)
      assert config != nil
      assert config.type == :webauthn
    end

    test "returns nil for tenant without webauthn" do
      other_tenant = insert(:tenant)
      assert Credentials.get_webauthn_config(other_tenant.id) == nil
    end
  end

  describe "get_oidc_configs/1" do
    test "returns only OIDC configs", %{tenant: tenant} do
      insert(:oidc_idp_config, tenant_id: tenant.id)

      oidc_configs = Credentials.get_oidc_configs(tenant.id)
      assert length(oidc_configs) >= 1
      assert Enum.all?(oidc_configs, fn c -> c.type == :oidc end)
    end
  end
end
