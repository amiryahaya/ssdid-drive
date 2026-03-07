defmodule SecureSharingWeb.FallbackControllerTest do
  @moduledoc """
  Tests for the FallbackController error handling.

  Tests all error cases to ensure proper HTTP status codes and messages.
  """

  use SecureSharingWeb.ConnCase, async: true

  alias SecureSharingWeb.FallbackController
  alias SecureSharing.Accounts.User

  describe "call/2 with Ecto.Changeset errors" do
    test "returns 422 with validation errors", %{conn: conn} do
      changeset =
        %User{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:email, "can't be blank")

      conn = FallbackController.call(conn, {:error, changeset})

      assert json_response(conn, 422)["error"]["code"] == "validation_error"
    end
  end

  describe "call/2 with common error atoms" do
    test "returns 404 for :not_found", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})

      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end

    test "returns 401 for :unauthorized", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unauthorized})

      assert json_response(conn, 401)["error"]["code"] == "unauthorized"
    end

    test "returns 401 for :invalid_credentials", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_credentials})

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
      assert response["error"]["message"] =~ "Invalid email or password"
    end

    test "returns 409 for :ambiguous_tenant", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :ambiguous_tenant})

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
      assert response["error"]["message"] =~ "tenant_slug"
    end

    test "returns 403 for :forbidden", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :forbidden})

      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end

    test "returns 403 for {:forbidden, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:forbidden, "Custom forbidden message"}})

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
      assert response["error"]["message"] == "Custom forbidden message"
    end

    test "returns 402 for :quota_exceeded", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :quota_exceeded})

      response = json_response(conn, 402)
      assert response["error"]["message"] =~ "quota exceeded"
    end
  end

  describe "call/2 with cross-tenant errors" do
    test "returns 403 for :cross_tenant_share", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :cross_tenant_share})

      response = json_response(conn, 403)
      assert response["error"]["message"] =~ "Cannot share across tenants"
    end

    test "returns 403 for :cross_tenant_operation", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :cross_tenant_operation})

      response = json_response(conn, 403)
      assert response["error"]["message"] =~ "Cross-tenant"
    end
  end

  describe "call/2 with recovery errors" do
    test "returns 409 for :config_exists", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :config_exists})

      response = json_response(conn, 409)
      assert response["error"]["message"] =~ "already exists"
    end

    test "returns 404 for :no_recovery_config", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :no_recovery_config})

      response = json_response(conn, 404)
      assert response["error"]["message"] =~ "No recovery configuration"
    end

    test "returns 412 for :threshold_not_reached", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :threshold_not_reached})

      response = json_response(conn, 412)
      assert response["error"]["message"] =~ "threshold"
    end

    test "returns 409 for :request_not_approvable", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :request_not_approvable})

      response = json_response(conn, 409)
      assert response["error"]["message"] =~ "approvable"
    end

    test "returns 410 for :request_expired", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :request_expired})

      response = json_response(conn, 410)
      assert response["error"]["message"] =~ "expired"
    end

    test "returns 412 for :share_not_accepted", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :share_not_accepted})

      response = json_response(conn, 412)
      assert response["error"]["message"] =~ "accepted"
    end

    test "returns 403 for :not_request_owner", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_request_owner})

      response = json_response(conn, 403)
      assert response["error"]["message"] =~ "owner"
    end

    test "returns 412 for :request_not_approved", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :request_not_approved})

      response = json_response(conn, 412)
      assert response["error"]["message"] =~ "approved"
    end

    test "returns 403 for :not_config_owner", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_config_owner})

      response = json_response(conn, 403)
      assert response["error"]["message"] =~ "owner"
    end

    test "returns 422 for :share_index_out_of_bounds", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :share_index_out_of_bounds})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "index"
    end

    test "returns 422 for :missing_share_index", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :missing_share_index})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "index"
    end
  end

  describe "call/2 with token errors" do
    test "returns 401 for :invalid_token", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_token})

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "Invalid or expired token"
    end

    test "returns 401 for :invalid_token_type", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_token_type})

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "token type"
    end

    test "returns 401 for :token_revoked", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :token_revoked})

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "revoked"
    end

    test "returns 401 for :signature_error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :signature_error})

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "signature"
    end
  end

  describe "call/2 with file/folder errors" do
    test "returns 422 for :cannot_delete_root", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :cannot_delete_root})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "root folder"
    end

    test "returns 412 for :blob_not_found", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :blob_not_found})

      response = json_response(conn, 412)
      assert response["error"]["message"] =~ "Blob not found"
    end
  end

  describe "call/2 with validation errors" do
    test "returns 400 for {:invalid_base64, field}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:invalid_base64, :encrypted_data}})

      response = json_response(conn, 400)
      assert response["error"]["message"] =~ "encrypted_data"
    end

    test "returns 400 for :invalid_base64", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_base64})

      response = json_response(conn, 400)
      assert response["error"]["message"] =~ "Base64"
    end

    test "returns 400 for :invalid_uuid", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_uuid})

      response = json_response(conn, 400)
      assert response["error"]["message"] =~ "UUID"
    end

    test "returns 400 for :missing_required_field", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :missing_required_field})

      response = json_response(conn, 400)
      assert response["error"]["message"] =~ "Missing required"
    end
  end

  describe "call/2 with tenant errors" do
    test "returns 404 for :tenant_not_found", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :tenant_not_found})

      response = json_response(conn, 404)
      assert response["error"]["message"] =~ "Tenant not found"
    end

    test "returns 422 for :self_removal", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :self_removal})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "Cannot remove yourself"
    end

    test "returns 409 for :already_member", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :already_member})

      response = json_response(conn, 409)
      assert response["error"]["message"] =~ "already a member"
    end

    test "returns 422 for :owner_transfer_required", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :owner_transfer_required})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "transfer ownership"
    end
  end

  describe "call/2 with generic error tuples" do
    test "returns 410 for {:error, :gone, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :gone, "Resource has been deleted"})

      response = json_response(conn, 410)
      assert response["error"]["message"] == "Resource has been deleted"
    end

    test "returns 409 for {:error, :conflict, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :conflict, "Resource conflict"})

      response = json_response(conn, 409)
      assert response["error"]["message"] == "Resource conflict"
    end

    test "returns 422 for {:error, :unprocessable_entity, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unprocessable_entity, "Cannot process"})

      response = json_response(conn, 422)
      assert response["error"]["message"] == "Cannot process"
    end

    test "returns 403 for {:error, :forbidden, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :forbidden, "Access denied"})

      response = json_response(conn, 403)
      assert response["error"]["message"] == "Access denied"
    end

    test "returns 400 for {:error, :bad_request, message}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :bad_request, "Bad input"})

      response = json_response(conn, 400)
      assert response["error"]["message"] == "Bad input"
    end

    test "returns 400 for {:error, {:bad_request, message}}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:bad_request, "Invalid request"}})

      response = json_response(conn, 400)
      assert response["error"]["message"] == "Invalid request"
    end

    test "returns 409 for {:error, {:conflict, message}}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:conflict, "Conflict occurred"}})

      response = json_response(conn, 409)
      assert response["error"]["message"] == "Conflict occurred"
    end

    test "returns 404 for {:error, {:not_found, message}}", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:not_found, "Item not found"}})

      response = json_response(conn, 404)
      assert response["error"]["message"] == "Item not found"
    end
  end

  describe "call/2 with boolean and nil fallbacks" do
    test "returns 403 for false", %{conn: conn} do
      conn = FallbackController.call(conn, false)

      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end

    test "returns 404 for nil", %{conn: conn} do
      conn = FallbackController.call(conn, nil)

      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end
  end
end
