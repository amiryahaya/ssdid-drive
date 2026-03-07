defmodule SecureSharingWeb.API.InviteController do
  @moduledoc """
  Public API controller for invitation acceptance.

  These endpoints are unauthenticated - they handle the invitation
  acceptance flow for new users who don't have accounts yet.

  ## Endpoints

  - `GET /api/invite/:token` - Get invitation info for display
  - `POST /api/invite/:token/accept` - Accept invitation and create account
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Audit
  alias SecureSharing.Invitations
  alias SecureSharing.Mailer
  alias SecureSharing.Emails.NotificationEmail
  alias SecureSharingWeb.Auth.Token

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  Get invitation info for display on the acceptance screen.

  GET /api/invite/:token

  Returns invitation details including:
  - Invitee email
  - Assigned role
  - Tenant name
  - Inviter name
  - Personal message (if any)
  - Expiration date
  - Validity status

  ## Response

  ### Valid invitation:
  ```json
  {
    "data": {
      "id": "uuid",
      "email": "user@example.com",
      "role": "member",
      "tenant_name": "Acme Corp",
      "inviter_name": "John Doe",
      "message": "Welcome to the team!",
      "expires_at": "2026-01-26T12:00:00Z",
      "valid": true
    }
  }
  ```

  ### Invalid invitation:
  ```json
  {
    "data": {
      "valid": false,
      "error_reason": "expired"
    }
  }
  ```
  """
  def show(conn, %{"token" => token}) do
    case Invitations.get_invitation_info(token) do
      {:ok, info} ->
        render(conn, :info, invitation: info)

      {:error, :not_found} ->
        render(conn, :info, invitation: %{valid: false, error_reason: :not_found})
    end
  end

  @doc """
  Accept an invitation and create a new user account.

  POST /api/invite/:token/accept

  ## Request Body
  ```json
  {
    "display_name": "Jane Smith",
    "password": "securepassword123",
    "public_keys": {
      "kem": "base64...",
      "sign": "base64...",
      "ml_kem": "base64...",
      "ml_dsa": "base64..."
    },
    "encrypted_master_key": "base64...",
    "encrypted_private_keys": "base64...",
    "key_derivation_salt": "base64..."
  }
  ```

  ## Response (201 Created)
  ```json
  {
    "data": {
      "user": {
        "id": "user-uuid",
        "email": "user@example.com",
        "display_name": "Jane Smith",
        "tenant_id": "tenant-uuid",
        "role": "member"
      },
      "access_token": "jwt...",
      "refresh_token": "jwt..."
    }
  }
  ```

  ## Errors
  - `400` - Invalid request body
  - `404` - Invitation not found
  - `410` - Invitation expired or revoked
  - `409` - Invitation already used
  - `422` - Validation error (password too short, etc.)
  """
  def accept(conn, %{"token" => token} = params) do
    user_attrs = %{
      display_name: params["display_name"],
      password: params["password"],
      public_keys: params["public_keys"],
      encrypted_master_key: params["encrypted_master_key"],
      encrypted_private_keys: params["encrypted_private_keys"],
      key_derivation_salt: params["key_derivation_salt"]
    }

    case Invitations.accept_invitation(token, user_attrs) do
      {:ok, user} ->
        # Get invitation for audit logging and email
        invitation = Invitations.get_invitation_by_token(token)

        # Generate tokens
        with {:ok, access_token} <-
               Token.generate_access_token(user, user.tenant_id, invitation.role),
             {:ok, refresh_token} <- Token.generate_refresh_token(user, user.tenant_id) do
          # Log successful registration via invitation
          audit_conn = %{conn | assigns: Map.put(conn.assigns, :tenant_id, user.tenant_id)}

          Audit.log_success(
            audit_conn,
            "user.register_via_invitation",
            "user",
            user.id,
            %{
              email: user.email,
              invitation_id: invitation.id,
              inviter_id: invitation.inviter_id
            }
          )

          # Send welcome email and notify inviter
          send_welcome_emails(user, invitation)

          conn
          |> put_status(:created)
          |> render(:accept,
            user: user,
            role: invitation.role,
            access_token: access_token,
            refresh_token: refresh_token
          )
        end

      {:error, :invitation_not_found} ->
        {:error, :not_found}

      {:error, :invitation_expired} ->
        {:error, :gone, "Invitation has expired"}

      {:error, :invitation_revoked} ->
        {:error, :gone, "Invitation has been revoked"}

      {:error, :invitation_already_used} ->
        {:error, :conflict, "Invitation has already been used"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  # Send welcome email to new user and notification to inviter
  defp send_welcome_emails(user, invitation) do
    # Send welcome email to new user
    Task.start(fn ->
      NotificationEmail.welcome_email(user, invitation.tenant)
      |> Mailer.deliver()
    end)

    # Notify inviter that their invitation was accepted
    Task.start(fn ->
      NotificationEmail.invitation_accepted_email(invitation.inviter, user, invitation.tenant)
      |> Mailer.deliver()
    end)
  end
end
