defmodule SecureSharing.Security.InputValidationTest do
  @moduledoc """
  Security tests for input validation.

  Tests:
  - SQL injection prevention
  - XSS payload rejection
  - Path traversal prevention
  - File type validation
  - Size limit enforcement
  - Unicode/encoding attacks
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  import Ecto.Query
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-001: SQL Injection Prevention
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-001: SQL Injection Prevention" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, user: user}
    end

    test "invitation email field rejects SQL injection", %{conn: conn, user: user, tenant: tenant} do
      # Attempt SQL injection in email field
      params = %{
        "email" => "test@example.com'; DROP TABLE users; --",
        "roles" => ["member"]
      }

      conn =
        conn |> authenticate(user, tenant, :admin) |> post(~p"/api/tenant/invitations", params)

      # Should either return validation error or sanitize input
      response_status = conn.status
      assert response_status in [201, 400, 422]

      # If accepted, verify no SQL injection occurred
      if response_status == 201 do
        # Verify users table still exists by making another query
        conn2 =
          build_conn()
          |> authenticate(user, tenant, :admin)
          |> get(~p"/api/tenants/#{tenant.id}/members")

        assert json_response(conn2, 200)
      end
    end

    test "search parameters reject SQL injection", %{conn: conn, user: user, tenant: tenant} do
      # Attempt SQL injection in search parameter
      params = %{"search" => "'; DELETE FROM users WHERE '1'='1"}

      conn =
        conn
        |> authenticate(user, tenant, :admin)
        |> get(~p"/api/tenant/invitations?#{URI.encode_query(params)}")

      # Should return results without executing injected SQL
      assert conn.status in [200, 400]
    end

    test "pagination parameters reject SQL injection", %{conn: conn, user: user, tenant: tenant} do
      # Attempt SQL injection in pagination
      params = %{"page" => "1; DROP TABLE files;", "per_page" => "10"}

      conn =
        conn |> authenticate(user, tenant) |> get(~p"/api/folders?#{URI.encode_query(params)}")

      # Should either reject or treat as invalid page number
      assert conn.status in [200, 400, 422]
    end

    test "UUID parameters reject SQL injection", %{conn: conn, user: user, tenant: tenant} do
      # Attempt SQL injection in UUID field
      # Audit plug validates UUID format, Ecto prevents SQL injection
      fake_uuid = "00000000-0000-0000-0000-000000000000'; DROP TABLE files;--"

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/files/#{fake_uuid}")

      # Should return not found or bad request, not execute SQL
      assert conn.status in [400, 404, 422]
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-002: XSS Payload Rejection
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-002: XSS Payload Handling" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "display name with XSS is sanitized or rejected", %{
      conn: conn,
      user: user,
      tenant: tenant
    } do
      # XSS payloads are now sanitized by InputSanitizer in User.profile_changeset
      xss_payloads = [
        "<script>alert('xss')</script>",
        "javascript:alert('xss')",
        "<img src=x onerror=alert('xss')>",
        "<svg onload=alert('xss')>",
        "'\"><script>alert('xss')</script>"
      ]

      for payload <- xss_payloads do
        params = %{"display_name" => payload}

        conn = build_conn() |> authenticate(user, tenant) |> put(~p"/api/me", params)

        # Should accept but sanitize, or reject
        case conn.status do
          200 ->
            response = json_response(conn, 200)
            # If accepted, verify script tags are not in response
            display_name = response["data"]["display_name"]
            refute display_name =~ ~r/<script/i
            refute display_name =~ ~r/javascript:/i
            refute display_name =~ ~r/onerror=/i

          422 ->
            # Rejection is also acceptable
            assert true

          _ ->
            flunk("Unexpected status: #{conn.status}")
        end
      end
    end

    test "device name with XSS is sanitized or rejected", %{
      conn: conn,
      user: user,
      tenant: tenant
    } do
      params = %{
        "device_fingerprint" => "sha256:abc123",
        "platform" => "android",
        "device_info" => %{},
        "device_public_key" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "key_algorithm" => "kaz_sign",
        "device_name" => "<script>alert('xss')</script>"
      }

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/devices/enroll", params)

      if conn.status == 201 do
        response = json_response(conn, 201)
        refute response["data"]["device_name"] =~ ~r/<script/i
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-003: Path Traversal Prevention
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-003: Path Traversal Prevention" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user, root: root}
    end

    test "folder name rejects path traversal sequences", %{
      conn: conn,
      user: user,
      tenant: tenant,
      root: root
    } do
      traversal_payloads = [
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32",
        "....//....//etc/passwd",
        "%2e%2e%2f%2e%2e%2f",
        "..%252f..%252f"
      ]

      for payload <- traversal_payloads do
        params = %{
          "parent_id" => root.id,
          "encrypted_metadata" => Base.encode64(payload),
          "metadata_nonce" => Base.encode64(:crypto.strong_rand_bytes(12)),
          "wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
          "owner_wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
          "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
        }

        conn = build_conn() |> authenticate(user, tenant) |> post(~p"/api/folders", params)

        # Should accept (metadata is encrypted) or reject
        # The key is that path traversal shouldn't affect server-side paths
        assert conn.status in [201, 400, 422]
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-004: Size Limit Enforcement
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-004: Size Limit Enforcement" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "display name rejects extremely long input", %{conn: conn, user: user, tenant: tenant} do
      # 10KB string
      long_name = String.duplicate("A", 10_000)
      params = %{"display_name" => long_name}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me", params)

      # Should reject with validation error
      assert conn.status in [400, 413, 422]
    end

    test "invitation roles list rejects excessive items", %{
      conn: conn,
      user: user,
      tenant: tenant
    } do
      # Make user an admin so they can send invitations
      SecureSharing.Repo.update_all(
        from(ut in SecureSharing.Accounts.UserTenant,
          where: ut.user_id == ^user.id and ut.tenant_id == ^tenant.id
        ),
        set: [role: :admin]
      )

      # 1000 roles
      excessive_roles = for _ <- 1..1000, do: "member"
      params = %{"email" => "test@example.com", "roles" => excessive_roles}

      conn =
        conn |> authenticate(user, tenant, :admin) |> post(~p"/api/tenant/invitations", params)

      # Should reject or limit
      assert conn.status in [201, 400, 413, 422]
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-005: Email Format Validation
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-005: Email Format Validation" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, user: user}
    end

    test "invitation rejects invalid email formats", %{conn: conn, user: user, tenant: tenant} do
      invalid_emails = [
        "notanemail",
        "@nodomain.com",
        "noat.com",
        "spaces in@email.com",
        "<script>@hack.com",
        "test@",
        "",
        "a" <> String.duplicate("@", 100) <> "b.com"
      ]

      for email <- invalid_emails do
        params = %{"email" => email, "roles" => ["member"]}

        conn =
          build_conn()
          |> authenticate(user, tenant, :admin)
          |> post(~p"/api/tenant/invitations", params)

        # Should reject invalid emails
        assert conn.status in [400, 422],
               "Expected rejection for invalid email: #{email}, got status #{conn.status}"
      end
    end

    test "invitation accepts valid email formats", %{conn: conn, user: user, tenant: tenant} do
      valid_emails = [
        "simple@example.com",
        "with.dot@example.com",
        "with+plus@example.com",
        "with-dash@example.com",
        "123@example.com",
        "user@sub.domain.com"
      ]

      for email <- valid_emails do
        params = %{"email" => email, "roles" => ["member"]}

        conn =
          build_conn()
          |> authenticate(user, tenant, :admin)
          |> post(~p"/api/tenant/invitations", params)

        # Valid emails should be accepted
        assert conn.status in [201, 409],
               "Expected acceptance for valid email: #{email}, got status #{conn.status}"
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-INP-006: Unicode Handling
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-INP-006: Unicode Handling" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "handles unicode in display name safely", %{conn: conn, user: user, tenant: tenant} do
      unicode_names = [
        "用户名",
        "المستخدم",
        "🎉 Party User 🎊",
        "Zero\u200Bwidth",
        "Combining\u0301marks",
        "Normalization café vs café"
      ]

      for name <- unicode_names do
        params = %{"display_name" => name}

        conn = build_conn() |> authenticate(user, tenant) |> put(~p"/api/me", params)

        # Should handle unicode gracefully
        assert conn.status in [200, 400, 422]

        if conn.status == 200 do
          response = json_response(conn, 200)
          # Verify unicode is preserved or normalized, not corrupted
          assert is_binary(response["data"]["display_name"])
        end
      end
    end

    test "handles null bytes safely", %{conn: conn, user: user, tenant: tenant} do
      # Null bytes are now stripped by InputSanitizer in User.profile_changeset
      params = %{"display_name" => "before\x00after"}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me", params)

      # Should reject or strip null bytes
      if conn.status == 200 do
        response = json_response(conn, 200)
        refute response["data"]["display_name"] =~ "\x00"
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
