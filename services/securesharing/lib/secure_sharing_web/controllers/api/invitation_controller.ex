defmodule SecureSharingWeb.API.InvitationController do
  @moduledoc """
  Authenticated API controller for invitation management.

  These endpoints require authentication and are used by admins/managers
  to create, list, and manage invitations for new users.

  ## Endpoints

  - `GET /api/tenant/invitations` - List tenant invitations
  - `POST /api/tenant/invitations` - Create new invitation
  - `GET /api/tenant/invitations/:id` - Get invitation details
  - `DELETE /api/tenant/invitations/:id` - Revoke invitation
  - `POST /api/tenant/invitations/:id/resend` - Resend invitation email
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts
  alias SecureSharing.Audit
  alias SecureSharing.Invitations
  alias SecureSharing.Mailer
  alias SecureSharing.Emails.NotificationEmail

  action_fallback SecureSharingWeb.FallbackController

  @app_url Application.compile_env(:secure_sharing, :app_url, "https://app.securesharing.example")

  @doc """
  List all invitations for the current tenant.

  GET /api/tenant/invitations

  ## Query Parameters
  - `status` - Filter by status (pending, accepted, expired, revoked)
  - `page` - Page number (default: 1)
  - `per_page` - Items per page (default: 20, max: 100)

  ## Response
  ```json
  {
    "data": [...],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total": 42,
      "total_pages": 3
    }
  }
  ```
  """
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id
    user = Accounts.get_user(conn.assigns.user_id)

    # Only admins/managers can list invitations
    if Invitations.can_invite?(user, tenant_id) do
      status = parse_status(params["status"])
      page = max(1, String.to_integer(params["page"] || "1"))
      per_page = min(100, max(1, String.to_integer(params["per_page"] || "20")))
      offset = (page - 1) * per_page

      invitations =
        Invitations.list_tenant_invitations(tenant_id,
          status: status,
          limit: per_page,
          offset: offset
        )

      total = Invitations.count_invitations(tenant_id, status)
      total_pages = ceil(total / per_page)

      pagination = %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: total_pages
      }

      render(conn, :index, invitations: invitations, pagination: pagination)
    else
      {:error, :forbidden}
    end
  end

  defp parse_status(nil), do: nil
  defp parse_status("pending"), do: :pending
  defp parse_status("accepted"), do: :accepted
  defp parse_status("expired"), do: :expired
  defp parse_status("revoked"), do: :revoked
  defp parse_status(_), do: nil

  @doc """
  Create a new invitation.

  POST /api/tenant/invitations

  ## Request Body
  ```json
  {
    "email": "newuser@example.com",
    "role": "member",
    "message": "Welcome to the team!"
  }
  ```

  ## Response (201 Created)
  Returns the created invitation.
  """
  def create(conn, params) do
    tenant_id = conn.assigns.tenant_id
    user = Accounts.get_user(conn.assigns.user_id)

    attrs = %{
      email: params["email"],
      role: params["role"] || "member",
      message: params["message"],
      tenant_id: tenant_id
    }

    case Invitations.create_invitation(user, attrs) do
      {:ok, invitation} ->
        # Preserve token before reloading (virtual field lost on db fetch)
        token = invitation.token

        # Load associations for email and response
        invitation = Invitations.get_invitation!(invitation.id)
        # Restore token on the reloaded struct
        invitation = %{invitation | token: token}

        # Send invitation email
        invite_url = build_invite_url(token)
        send_invitation_email(invitation, invite_url)

        # Log the invitation creation
        Audit.log_success(
          conn,
          "invitation.created",
          "invitation",
          invitation.id,
          %{email: invitation.email, role: invitation.role}
        )

        conn
        |> put_status(:created)
        |> render(:create, invitation: invitation)

      {:error, :not_authorized} ->
        {:error, :forbidden, "You are not authorized to send invitations"}

      {:error, :email_already_registered} ->
        {:error, :conflict, "This email is already registered in the tenant"}

      {:error, :pending_invitation_exists} ->
        {:error, :conflict, "A pending invitation already exists for this email"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Get invitation details.

  GET /api/tenant/invitations/:id
  """
  def show(conn, %{"id" => id}) do
    with :ok <- validate_uuid(id) do
      tenant_id = conn.assigns.tenant_id
      user = Accounts.get_user(conn.assigns.user_id)

      if Invitations.can_invite?(user, tenant_id) do
        case Invitations.get_invitation(id) do
          nil ->
            {:error, :not_found}

          invitation ->
            if invitation.tenant_id == tenant_id do
              render(conn, :show, invitation: invitation)
            else
              {:error, :not_found}
            end
        end
      else
        {:error, :forbidden}
      end
    end
  end

  @doc """
  Revoke a pending invitation.

  DELETE /api/tenant/invitations/:id
  """
  def revoke(conn, %{"id" => id}) do
    with :ok <- validate_uuid(id) do
      tenant_id = conn.assigns.tenant_id
      user = Accounts.get_user(conn.assigns.user_id)

      if Invitations.can_invite?(user, tenant_id) do
        case Invitations.get_invitation(id) do
          nil ->
            {:error, :not_found}

          invitation ->
            if invitation.tenant_id == tenant_id do
              case Invitations.revoke_invitation(invitation) do
                {:ok, _invitation} ->
                  Audit.log_success(
                    conn,
                    "invitation.revoked",
                    "invitation",
                    id,
                    %{email: invitation.email}
                  )

                  send_resp(conn, :no_content, "")

                {:error, :cannot_revoke} ->
                  {:error, :unprocessable_entity, "Only pending invitations can be revoked"}
              end
            else
              {:error, :not_found}
            end
        end
      else
        {:error, :forbidden}
      end
    end
  end

  @doc """
  Resend an invitation email.

  POST /api/tenant/invitations/:id/resend

  Generates a new token and extends the expiration date.
  """
  def resend(conn, %{"id" => id}) do
    with :ok <- validate_uuid(id) do
      tenant_id = conn.assigns.tenant_id
      user = Accounts.get_user(conn.assigns.user_id)

      if Invitations.can_invite?(user, tenant_id) do
        case Invitations.get_invitation(id) do
          nil ->
            {:error, :not_found}

          invitation ->
            if invitation.tenant_id == tenant_id do
              case Invitations.resend_invitation(invitation) do
                {:ok, updated_invitation} ->
                  # Load associations for email
                  updated_invitation =
                    updated_invitation
                    |> Map.put(:tenant, invitation.tenant)
                    |> Map.put(:inviter, invitation.inviter)

                  # Send new invitation email with new token
                  invite_url = build_invite_url(updated_invitation.token)
                  send_invitation_email(updated_invitation, invite_url)

                  Audit.log_success(
                    conn,
                    "invitation.resent",
                    "invitation",
                    id,
                    %{email: invitation.email}
                  )

                  # Return the updated invitation (without the token in response)
                  render(conn, :show, invitation: Invitations.get_invitation!(id))

                {:error, :cannot_resend} ->
                  {:error, :unprocessable_entity, "Only pending invitations can be resent"}
              end
            else
              {:error, :not_found}
            end
        end
      else
        {:error, :forbidden}
      end
    end
  end

  # Helpers

  defp validate_uuid(id) do
    # UUIDv7 format: 8-4-4-4-12 hex characters with hyphens
    uuid_regex = ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

    if Regex.match?(uuid_regex, id) do
      :ok
    else
      {:error, :invalid_uuid}
    end
  end

  defp build_invite_url(token) do
    "#{@app_url}/invite/#{token}"
  end

  defp send_invitation_email(invitation, invite_url) do
    Task.start(fn ->
      NotificationEmail.new_user_invitation_email(invitation, invite_url)
      |> Mailer.deliver()
    end)
  end
end
