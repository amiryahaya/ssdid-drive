defmodule SecureSharing.AccountsTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Accounts
  alias SecureSharing.Accounts.{Tenant, User}

  describe "tenants" do
    test "create_tenant/1 with valid data creates a tenant" do
      attrs = %{name: "Acme Corp", slug: "acme-corp"}

      assert {:ok, %Tenant{} = tenant} = Accounts.create_tenant(attrs)
      assert tenant.name == "Acme Corp"
      assert tenant.slug == "acme-corp"
      assert tenant.storage_quota_bytes == 10_737_418_240
    end

    test "create_tenant/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_tenant(%{name: ""})
    end

    test "create_tenant/1 with duplicate slug returns error" do
      insert(:tenant, slug: "existing-slug")

      assert {:error, changeset} =
               Accounts.create_tenant(%{name: "New Tenant", slug: "existing-slug"})

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "get_tenant/1 returns tenant by id" do
      tenant = insert(:tenant)
      assert Accounts.get_tenant(tenant.id).id == tenant.id
    end

    test "get_tenant_by_slug/1 returns tenant by slug" do
      tenant = insert(:tenant, slug: "test-slug")
      assert Accounts.get_tenant_by_slug("test-slug").id == tenant.id
    end

    test "create_tenant/1 with pqc_algorithm sets the algorithm" do
      attrs = %{name: "NIST Tenant", slug: "nist-tenant", pqc_algorithm: :nist}

      assert {:ok, %Tenant{} = tenant} = Accounts.create_tenant(attrs)
      assert tenant.pqc_algorithm == :nist
    end

    test "create_tenant/1 defaults to kaz algorithm" do
      attrs = %{name: "Default Tenant", slug: "default-tenant"}

      assert {:ok, %Tenant{} = tenant} = Accounts.create_tenant(attrs)
      assert tenant.pqc_algorithm == :kaz
    end
  end

  describe "users" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "register_user/1 with valid data creates a user", %{tenant: tenant} do
      attrs = %{
        email: "test@example.com",
        password: "secure_password_123",
        tenant_id: tenant.id,
        public_keys: %{ml_kem: "key1", ml_dsa: "key2"},
        encrypted_private_keys: <<1, 2, 3>>,
        encrypted_master_key: <<4, 5, 6>>,
        key_derivation_salt: <<7, 8, 9>>
      }

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.email == "test@example.com"
      assert user.tenant_id == tenant.id
      # Keys are stored as atom keys from the changeset cast
      assert user.public_keys == %{ml_kem: "key1", ml_dsa: "key2"}
      assert user.encrypted_master_key == <<4, 5, 6>>
      # Password should be hashed, not stored plaintext
      refute user.password
      assert user.hashed_password
    end

    test "register_user/1 requires email", %{tenant: tenant} do
      attrs = %{password: "secure_password_123", tenant_id: tenant.id}

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "can't be blank" in errors_on(changeset).email
    end

    test "register_user/1 requires minimum password length", %{tenant: tenant} do
      attrs = %{email: "test@example.com", password: "short", tenant_id: tenant.id}

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "register_user/1 enforces unique email within tenant", %{tenant: tenant} do
      insert(:user, email: "existing@example.com", tenant_id: tenant.id)

      attrs = %{
        email: "existing@example.com",
        password: "secure_password_123",
        tenant_id: tenant.id
      }

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "has already been taken" in errors_on(changeset).tenant_id
    end

    test "register_user/1 allows same email in different tenants" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      attrs1 = %{
        email: "same@example.com",
        password: "secure_password_123",
        tenant_id: tenant1.id
      }

      attrs2 = %{
        email: "same@example.com",
        password: "secure_password_123",
        tenant_id: tenant2.id
      }

      assert {:ok, _user1} = Accounts.register_user(attrs1)
      assert {:ok, _user2} = Accounts.register_user(attrs2)
    end

    test "get_user/1 returns user by id", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      assert Accounts.get_user(user.id).id == user.id
    end

    test "get_user_by_email/2 returns user by tenant and email", %{tenant: tenant} do
      user = insert(:user, email: "find@example.com", tenant_id: tenant.id)
      assert Accounts.get_user_by_email(tenant.id, "find@example.com").id == user.id
    end

    test "get_user_by_email/2 returns nil for wrong tenant", %{tenant: tenant} do
      other_tenant = insert(:tenant)
      insert(:user, email: "find@example.com", tenant_id: tenant.id)

      assert Accounts.get_user_by_email(other_tenant.id, "find@example.com") == nil
    end
  end

  describe "authentication" do
    setup do
      tenant = insert(:tenant)
      # Create user with known password
      {:ok, user} =
        Accounts.register_user(%{
          email: "auth@example.com",
          password: "correct_password_123",
          tenant_id: tenant.id
        })

      {:ok, user: user, tenant: tenant}
    end

    test "authenticate_user/2 returns user with correct password", %{user: user} do
      assert {:ok, authenticated} =
               Accounts.authenticate_user("auth@example.com", "correct_password_123")

      assert authenticated.id == user.id
    end

    test "authenticate_user/2 returns error with wrong password" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("auth@example.com", "wrong_password")
    end

    test "authenticate_user/2 returns error for non-existent user" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("nonexistent@example.com", "any_password")
    end

    test "authenticate_user/3 authenticates within tenant", %{user: user, tenant: tenant} do
      assert {:ok, authenticated} =
               Accounts.authenticate_user(tenant.id, "auth@example.com", "correct_password_123")

      assert authenticated.id == user.id
    end

    test "authenticate_user/2 with duplicate emails returns invalid_credentials for wrong password" do
      # Create two tenants with users having the same email but different passwords
      tenant1 = insert(:tenant, slug: "tenant-one")
      tenant2 = insert(:tenant, slug: "tenant-two")

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password_123"),
        tenant_id: tenant1.id
      )

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password_456"),
        tenant_id: tenant2.id
      )

      # Wrong password for all users - returns invalid_credentials (doesn't reveal ambiguity)
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("duplicate@example.com", "wrong_password")
    end

    test "authenticate_user/2 with duplicate emails succeeds when password matches exactly one user" do
      tenant1 = insert(:tenant, slug: "tenant-one")
      tenant2 = insert(:tenant, slug: "tenant-two")

      user1 =
        insert(:user,
          email: "duplicate@example.com",
          hashed_password: Bcrypt.hash_pwd_salt("password_123"),
          tenant_id: tenant1.id
        )

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password_456"),
        tenant_id: tenant2.id
      )

      # Password valid for exactly one user - authenticates successfully
      assert {:ok, authenticated} =
               Accounts.authenticate_user("duplicate@example.com", "password_123")

      assert authenticated.id == user1.id
    end

    test "authenticate_user/2 returns ambiguous_tenant when password matches multiple users" do
      # Create two tenants with users having the SAME password
      tenant1 = insert(:tenant, slug: "tenant-one")
      tenant2 = insert(:tenant, slug: "tenant-two")

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("shared_password"),
        tenant_id: tenant1.id
      )

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("shared_password"),
        tenant_id: tenant2.id
      )

      # Password valid for multiple users - requires tenant specification
      # Safe to reveal since they proved knowledge of the password
      assert {:error, :ambiguous_tenant} =
               Accounts.authenticate_user("duplicate@example.com", "shared_password")
    end

    test "authenticate_user/3 with tenant context works for duplicate emails" do
      tenant1 = insert(:tenant, slug: "tenant-one")
      tenant2 = insert(:tenant, slug: "tenant-two")

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password_123"),
        tenant_id: tenant1.id
      )

      insert(:user,
        email: "duplicate@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password_456"),
        tenant_id: tenant2.id
      )

      # With tenant context, should work correctly
      assert {:ok, user1} =
               Accounts.authenticate_user(tenant1.id, "duplicate@example.com", "password_123")

      assert user1.tenant_id == tenant1.id

      assert {:ok, user2} =
               Accounts.authenticate_user(tenant2.id, "duplicate@example.com", "password_456")

      assert user2.tenant_id == tenant2.id
    end
  end

  describe "key_bundle" do
    test "get_key_bundle/1 returns encrypted key material" do
      tenant = insert(:tenant)

      user =
        insert(:user,
          tenant_id: tenant.id,
          encrypted_master_key: <<1, 2, 3>>,
          encrypted_private_keys: <<4, 5, 6>>,
          key_derivation_salt: <<7, 8, 9>>,
          public_keys: %{"ml_kem" => "pubkey"}
        )

      assert {:ok, bundle} = Accounts.get_key_bundle(user)
      assert bundle.encrypted_master_key == <<1, 2, 3>>
      assert bundle.encrypted_private_keys == <<4, 5, 6>>
      assert bundle.key_derivation_salt == <<7, 8, 9>>
      assert bundle.public_keys == %{"ml_kem" => "pubkey"}
    end
  end

  describe "email validation (RFC 5322 compliant)" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "accepts valid standard email addresses", %{tenant: tenant} do
      valid_emails = [
        "user@example.com",
        "user.name@example.com",
        "user+tag@example.com",
        "user@subdomain.example.com",
        "user@example.co.uk",
        "firstname.lastname@company.org",
        "email@123.123.123.123.com",
        "1234567890@example.com",
        "_______@example.com"
      ]

      for email <- valid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:ok, user} = Accounts.register_user(attrs),
               "Expected #{email} to be valid"

        assert user.email == email
      end
    end

    test "accepts valid emails with special characters in local part", %{tenant: tenant} do
      valid_emails = [
        "user!def@example.com",
        "user#comment@example.com",
        "user$money@example.com",
        "user%percent@example.com",
        "user&and@example.com",
        "user'quote@example.com",
        "user*star@example.com",
        "user/slash@example.com",
        "user=equals@example.com",
        "user?question@example.com",
        "user^caret@example.com",
        "user`backtick@example.com",
        "user{brace}@example.com",
        "user|pipe@example.com",
        "user~tilde@example.com"
      ]

      for email <- valid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:ok, _user} = Accounts.register_user(attrs),
               "Expected #{email} to be valid"
      end
    end

    test "rejects emails without domain TLD", %{tenant: tenant} do
      # The old regex would accept "a@b" - the new one requires at least one dot in domain
      invalid_emails = [
        "user@localhost",
        "a@b",
        "test@domain"
      ]

      for email <- invalid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:error, changeset} = Accounts.register_user(attrs),
               "Expected #{email} to be rejected"

        assert "must be a valid email address" in errors_on(changeset).email
      end
    end

    test "rejects emails with missing parts", %{tenant: tenant} do
      invalid_emails = [
        "@example.com",
        "user@",
        "@",
        "user",
        ""
      ]

      for email <- invalid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:error, changeset} = Accounts.register_user(attrs),
               "Expected #{email} to be rejected"

        assert errors_on(changeset).email != nil
      end
    end

    test "rejects emails with spaces", %{tenant: tenant} do
      invalid_emails = [
        "user @example.com",
        "user@ example.com",
        " user@example.com",
        "user@example.com ",
        "us er@example.com"
      ]

      for email <- invalid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:error, changeset} = Accounts.register_user(attrs),
               "Expected '#{email}' to be rejected"

        assert "must be a valid email address" in errors_on(changeset).email
      end
    end

    test "rejects emails with multiple @ symbols", %{tenant: tenant} do
      attrs = %{
        email: "user@@example.com",
        password: "secure_password_123",
        tenant_id: tenant.id
      }

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "must be a valid email address" in errors_on(changeset).email
    end

    test "rejects emails with invalid domain characters", %{tenant: tenant} do
      invalid_emails = [
        "user@exam ple.com",
        "user@example..com",
        "user@-example.com"
      ]

      for email <- invalid_emails do
        attrs = %{
          email: email,
          password: "secure_password_123",
          tenant_id: tenant.id
        }

        assert {:error, changeset} = Accounts.register_user(attrs),
               "Expected #{email} to be rejected"

        assert "must be a valid email address" in errors_on(changeset).email
      end
    end

    test "enforces maximum email length", %{tenant: tenant} do
      # Create an email > 160 characters
      long_local = String.duplicate("a", 150)
      long_email = "#{long_local}@example.com"

      attrs = %{
        email: long_email,
        password: "secure_password_123",
        tenant_id: tenant.id
      }

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end
  end
end
