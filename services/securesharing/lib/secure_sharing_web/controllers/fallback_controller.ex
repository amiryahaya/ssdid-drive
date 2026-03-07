defmodule SecureSharingWeb.FallbackController do
  @moduledoc """
  Centralized error handling for API controllers.

  Used as `action_fallback` to translate error tuples into proper HTTP responses.
  """

  use SecureSharingWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json")
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Invalid email or password")
  end

  def call(conn, {:error, :ambiguous_tenant}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json",
      message: "Email exists in multiple tenants. Please specify tenant_slug."
    )
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json")
  end

  def call(conn, {:error, {:forbidden, message}}) when is_binary(message) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: message)
  end

  def call(conn, {:error, :quota_exceeded}) do
    conn
    |> put_status(:payment_required)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("402.json", message: "Storage quota exceeded")
  end

  def call(conn, {:error, :cross_tenant_share}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: "Cannot share across tenants")
  end

  def call(conn, {:error, :cross_tenant_operation}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: "Cross-tenant operation not allowed")
  end

  def call(conn, {:error, :config_exists}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: "Recovery configuration already exists")
  end

  def call(conn, {:error, :no_recovery_config}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("404.json", message: "No recovery configuration found")
  end

  def call(conn, {:error, :threshold_not_reached}) do
    conn
    |> put_status(:precondition_failed)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("412.json", message: "Recovery approval threshold not reached")
  end

  def call(conn, {:error, :request_not_approvable}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: "Recovery request is not in an approvable state")
  end

  def call(conn, {:error, :request_expired}) do
    conn
    |> put_status(:gone)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("410.json", message: "Recovery request has expired")
  end

  def call(conn, {:error, :share_not_accepted}) do
    conn
    |> put_status(:precondition_failed)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("412.json", message: "Recovery share must be accepted before approving")
  end

  def call(conn, {:error, :not_request_owner}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: "Not the owner of this recovery request")
  end

  def call(conn, {:error, :request_not_approved}) do
    conn
    |> put_status(:precondition_failed)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("412.json", message: "Recovery request must be approved before finalizing")
  end

  def call(conn, {:error, :not_config_owner}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: "Not the owner of this recovery config")
  end

  def call(conn, {:error, :share_index_out_of_bounds}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Share index must be between 1 and total_shares")
  end

  def call(conn, {:error, :missing_share_index}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Share index is required")
  end

  def call(conn, {:error, :token_expired}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Token has expired")
  end

  def call(conn, {:error, :invalid_token}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Invalid or expired token")
  end

  def call(conn, {:error, :invalid_token_type}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Invalid token type")
  end

  def call(conn, {:error, :tenant_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("404.json", message: "Tenant not found")
  end

  def call(conn, {:error, :cannot_delete_root}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Cannot delete root folder")
  end

  def call(conn, {:error, {:invalid_base64, field}}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "Invalid Base64 encoding for field: #{field}")
  end

  def call(conn, {:error, :invalid_base64}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "Invalid Base64 encoding")
  end

  def call(conn, {:error, :invalid_uuid}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "Invalid UUID format")
  end

  def call(conn, {:error, :missing_required_field}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "Missing required field")
  end

  def call(conn, {:error, :token_revoked}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Token has been revoked")
  end

  def call(conn, {:error, :blob_not_found}) do
    conn
    |> put_status(:precondition_failed)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("412.json", message: "Blob not found in storage. Upload may not have completed.")
  end

  # Generic error handlers with custom messages
  def call(conn, {:error, :gone, message}) do
    conn
    |> put_status(:gone)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("410.json", message: message)
  end

  def call(conn, {:error, :conflict, message}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: message)
  end

  def call(conn, {:error, :unprocessable_entity, message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: message)
  end

  def call(conn, {:error, :forbidden, message}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("403.json", message: message)
  end

  def call(conn, {:error, :bad_request, message}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: message)
  end

  def call(conn, {:error, {:bad_request, message}}) when is_binary(message) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: message)
  end

  def call(conn, {:error, {:conflict, message}}) when is_binary(message) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: message)
  end

  # Handle signature verification errors from Token.verify
  def call(conn, {:error, :signature_error}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "Invalid token signature")
  end

  # Handle self-removal error (user trying to remove themselves)
  def call(conn, {:error, :self_removal}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Cannot remove yourself from tenant")
  end

  # Handle not_found with custom message
  def call(conn, {:error, {:not_found, message}}) when is_binary(message) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("404.json", message: message)
  end

  # Handle already_member error
  def call(conn, {:error, :already_member}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: "User is already a member of this tenant")
  end

  # Handle owner_transfer_required error
  def call(conn, {:error, :owner_transfer_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Must transfer ownership before leaving tenant")
  end

  # WebAuthn / OIDC auth errors
  def call(conn, {:error, :challenge_expired}) do
    conn
    |> put_status(:gone)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("410.json", message: "Authentication challenge has expired")
  end

  def call(conn, {:error, :challenge_not_found}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "Authentication challenge not found or already used")
  end

  def call(conn, {:error, :credential_already_registered}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("409.json", message: "Credential is already registered")
  end

  def call(conn, {:error, :webauthn_verification_failed}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "WebAuthn verification failed")
  end

  def call(conn, {:error, :counter_rollback}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json",
      message: "Credential counter rollback detected (possible cloned authenticator)"
    )
  end

  def call(conn, {:error, :provider_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("404.json", message: "Identity provider not found")
  end

  def call(conn, {:error, :oidc_callback_failed}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("401.json", message: "OIDC authentication failed")
  end

  def call(conn, {:error, :state_mismatch}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "OIDC state mismatch")
  end

  def call(conn, {:error, :oidc_token_exchange_failed}) do
    conn
    |> put_status(:bad_gateway)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("502.json", message: "Failed to exchange authorization code with identity provider")
  end

  def call(conn, {:error, :pii_service_disabled}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("400.json", message: "PII detection is not enabled for this deployment")
  end

  def call(conn, {:error, :pii_service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("503.json", message: "PII service is temporarily unavailable")
  end

  def call(conn, {:error, :oidc_discovery_failed}) do
    conn
    |> put_status(:bad_gateway)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("502.json", message: "Failed to fetch identity provider configuration")
  end

  def call(conn, {:error, :last_credential}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SecureSharingWeb.ErrorJSON)
    |> render("422.json", message: "Cannot delete last credential")
  end

  # Handle `false` from access checks
  def call(conn, false) do
    call(conn, {:error, :forbidden})
  end

  # Handle `nil` from get operations
  def call(conn, nil) do
    call(conn, {:error, :not_found})
  end
end
