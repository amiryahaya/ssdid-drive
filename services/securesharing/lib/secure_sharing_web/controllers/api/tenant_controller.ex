defmodule SecureSharingWeb.API.TenantController do
  @moduledoc """
  Controller for multi-tenant user operations.

  Provides endpoints for:
  - Listing user's tenants
  - Switching active tenant
  - Managing tenant membership (invites, removals, role changes)
  - Handling invitations (list, accept, decline)
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Accounts
  alias SecureSharing.Audit
  alias SecureSharing.Mailer
  alias SecureSharing.Emails.NotificationEmail
  alias SecureSharingWeb.Auth.Token
  alias SecureSharingWeb.NotificationChannel

  action_fallback SecureSharingWeb.FallbackController

  # Roles that can manage tenant members
  @admin_roles [:owner, :admin]

  @doc """
  List all tenants the current user belongs to.

  GET /api/tenants

  Response:
  ```json
  {
    "data": [
      {"id": "...", "name": "Acme Corp", "slug": "acme", "role": "admin"},
      {"id": "...", "name": "Consulting Inc", "slug": "consulting", "role": "member"}
    ]
  }
  ```
  """
  def index(conn, _params) do
    user_id = conn.assigns[:user_id]
    tenants = Accounts.get_user_tenants(user_id)

    render(conn, :tenants, tenants: tenants)
  end

  @doc """
  Switch to a different tenant.

  POST /api/tenant/switch

  Request body:
  ```json
  {
    "tenant_id": "uuid"
  }
  ```

  Response:
  ```json
  {
    "data": {
      "current_tenant_id": "...",
      "role": "admin",
      "access_token": "...",
      "refresh_token": "...",
      "expires_in": 900,
      "token_type": "Bearer"
    }
  }
  ```
  """
  def switch(conn, %{"tenant_id" => tenant_id}) do
    user_id = conn.assigns[:user_id]

    case Accounts.get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :forbidden}

      %{status: "active", role: role} ->
        user = Accounts.get_user!(user_id)

        with {:ok, tokens} <- Token.generate_tokens(user, tenant_id, role) do
          # Log tenant switch
          Audit.log_success(conn, "tenant.switch", "tenant", tenant_id, %{
            from_tenant_id: conn.assigns[:tenant_id],
            to_tenant_id: tenant_id
          })

          render(conn, :switch_tenant,
            tenant_id: tenant_id,
            role: role,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token
          )
        end

      %{status: status} ->
        {:error, {:forbidden, "Tenant access is #{status}"}}
    end
  end

  @doc """
  Leave a tenant (remove self from tenant).

  DELETE /api/tenants/:id/leave

  Note: Users cannot leave a tenant if they are the only owner.
  """
  def leave(conn, %{"id" => tenant_id}) do
    user_id = conn.assigns[:user_id]

    case Accounts.get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :not_found}

      %{role: :owner} ->
        # Check if there are other owners
        members = Accounts.list_tenant_members(tenant_id)
        owner_count = Enum.count(members, fn m -> m.role == :owner end)

        if owner_count <= 1 do
          {:error,
           {:conflict, "Cannot leave tenant as the only owner. Transfer ownership first."}}
        else
          do_leave_tenant(conn, user_id, tenant_id)
        end

      _user_tenant ->
        do_leave_tenant(conn, user_id, tenant_id)
    end
  end

  defp do_leave_tenant(conn, user_id, tenant_id) do
    case Accounts.remove_user_from_tenant(user_id, tenant_id) do
      {:ok, _} ->
        Audit.log_success(conn, "tenant.leave", "tenant", tenant_id)
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get current tenant configuration.

  GET /api/tenant/config

  Legacy endpoint for backward compatibility.
  Returns configuration of the currently selected tenant.
  """
  def config(conn, _params) do
    tenant_id = conn.assigns[:tenant_id]

    case Accounts.get_tenant(tenant_id) do
      nil ->
        {:error, :not_found}

      tenant ->
        render(conn, :config, tenant: tenant)
    end
  end

  # ==================== Member Management ====================

  @doc """
  List all members of a tenant.

  GET /api/tenants/:tenant_id/members

  Requires admin or owner role in the tenant.
  """
  def list_members(conn, %{"tenant_id" => tenant_id}) do
    user_id = conn.assigns[:user_id]

    with {:ok, _} <- authorize_admin(user_id, tenant_id) do
      members = Accounts.list_tenant_members(tenant_id)
      render(conn, :members, members: members)
    end
  end

  @doc """
  Invite a user to a tenant.

  POST /api/tenants/:tenant_id/members

  Request body:
  ```json
  {
    "email": "user@example.com",
    "role": "member"  // optional, defaults to "member"
  }
  ```

  Requires admin or owner role in the tenant.
  """
  def invite_member(conn, %{"tenant_id" => tenant_id, "email" => email} = params) do
    user_id = conn.assigns[:user_id]
    role = parse_role(params["role"])

    with {:ok, _} <- authorize_admin(user_id, tenant_id),
         {:ok, invitee} <- get_user_by_email(email),
         :ok <- check_not_already_member(invitee.id, tenant_id),
         {:ok, user_tenant} <-
           Accounts.invite_user_to_tenant(invitee.id, tenant_id, user_id, role) do
      # Get tenant and inviter for notification (these are already validated)
      tenant = Accounts.get_tenant(tenant_id)
      inviter = Accounts.get_user!(user_id)

      Audit.log_success(conn, "tenant.invite", "user_tenant", user_tenant.id, %{
        invitee_email: email,
        role: role
      })

      # Send invitation email notification
      NotificationEmail.invitation_email(invitee, tenant, inviter)
      |> Mailer.deliver()

      # Send real-time notification via WebSocket
      NotificationChannel.broadcast_tenant_invitation(invitee.id, tenant, inviter)

      render(conn, :invitation, invitation: user_tenant, invitee: invitee)
    end
  end

  @doc """
  Update a member's role in a tenant.

  PUT /api/tenants/:tenant_id/members/:user_id/role

  Request body:
  ```json
  {
    "role": "admin"
  }
  ```

  Requires owner role (only owners can change roles).
  """
  def update_member_role(conn, %{
        "tenant_id" => tenant_id,
        "user_id" => target_user_id,
        "role" => role
      }) do
    user_id = conn.assigns[:user_id]
    new_role = parse_role(role)

    with {:ok, :owner} <- authorize_owner(user_id, tenant_id),
         :ok <- check_not_self(user_id, target_user_id),
         {:ok, user_tenant} <-
           Accounts.update_user_role_in_tenant(target_user_id, tenant_id, new_role) do
      Audit.log_success(conn, "tenant.update_role", "user_tenant", user_tenant.id, %{
        target_user_id: target_user_id,
        new_role: new_role
      })

      render(conn, :member, member: user_tenant)
    end
  end

  @doc """
  Remove a member from a tenant.

  DELETE /api/tenants/:tenant_id/members/:user_id

  Requires admin or owner role. Owners cannot be removed (they must transfer ownership first).
  """
  def remove_member(conn, %{"tenant_id" => tenant_id, "user_id" => target_user_id}) do
    user_id = conn.assigns[:user_id]

    with {:ok, _} <- authorize_admin(user_id, tenant_id),
         :ok <- check_not_self(user_id, target_user_id),
         :ok <- check_not_owner(target_user_id, tenant_id),
         {:ok, _} <- Accounts.remove_user_from_tenant(target_user_id, tenant_id) do
      Audit.log_success(conn, "tenant.remove_member", "tenant", tenant_id, %{
        removed_user_id: target_user_id
      })

      send_resp(conn, :no_content, "")
    end
  end

  # ==================== Invitations ====================

  @doc """
  List pending invitations for the current user.

  GET /api/invitations
  """
  def list_invitations(conn, _params) do
    user_id = conn.assigns[:user_id]
    invitations = Accounts.get_pending_invitations(user_id)
    render(conn, :invitations, invitations: invitations)
  end

  @doc """
  Accept a tenant invitation.

  POST /api/invitations/:id/accept
  """
  def accept_invitation(conn, %{"id" => invitation_id}) do
    user_id = conn.assigns[:user_id]

    with {:ok, user_tenant} <- get_user_invitation(user_id, invitation_id),
         {:ok, updated} <- Accounts.accept_tenant_invitation(user_id, user_tenant.tenant_id) do
      Audit.log_success(conn, "tenant.accept_invitation", "user_tenant", updated.id, %{
        tenant_id: user_tenant.tenant_id
      })

      render(conn, :invitation_accepted, user_tenant: updated)
    end
  end

  @doc """
  Decline a tenant invitation.

  POST /api/invitations/:id/decline
  """
  def decline_invitation(conn, %{"id" => invitation_id}) do
    user_id = conn.assigns[:user_id]

    with {:ok, user_tenant} <- get_user_invitation(user_id, invitation_id),
         {:ok, _} <- Accounts.decline_tenant_invitation(user_id, user_tenant.tenant_id) do
      Audit.log_success(conn, "tenant.decline_invitation", "user_tenant", invitation_id, %{
        tenant_id: user_tenant.tenant_id
      })

      send_resp(conn, :no_content, "")
    end
  end

  # ==================== Private Helpers ====================

  defp authorize_admin(user_id, tenant_id) do
    case Accounts.get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :forbidden}

      %{role: role} when role in @admin_roles ->
        {:ok, role}

      _ ->
        {:error, {:forbidden, "Admin or owner role required"}}
    end
  end

  defp authorize_owner(user_id, tenant_id) do
    case Accounts.get_user_tenant(user_id, tenant_id) do
      nil ->
        {:error, :forbidden}

      %{role: :owner} ->
        {:ok, :owner}

      _ ->
        {:error, {:forbidden, "Owner role required"}}
    end
  end

  defp get_user_by_email(email) do
    case Accounts.get_user_by_email(email) do
      nil -> {:error, {:not_found, "User not found with email: #{email}"}}
      user -> {:ok, user}
    end
  end

  defp check_not_already_member(user_id, tenant_id) do
    case Accounts.get_user_tenant(user_id, tenant_id) do
      nil -> :ok
      %{status: "pending"} -> {:error, {:conflict, "User already has a pending invitation"}}
      _ -> {:error, {:conflict, "User is already a member of this tenant"}}
    end
  end

  defp check_not_self(user_id, target_user_id) do
    if user_id == target_user_id do
      {:error, {:bad_request, "Cannot perform this action on yourself"}}
    else
      :ok
    end
  end

  defp check_not_owner(user_id, tenant_id) do
    case Accounts.get_user_tenant(user_id, tenant_id) do
      %{role: :owner} ->
        {:error, {:conflict, "Cannot remove an owner. Transfer ownership first."}}

      _ ->
        :ok
    end
  end

  defp get_user_invitation(user_id, invitation_id) do
    case Accounts.get_user_tenant_by_id(invitation_id) do
      nil ->
        {:error, :not_found}

      %{user_id: ^user_id, status: "pending"} = user_tenant ->
        {:ok, user_tenant}

      %{user_id: ^user_id} ->
        {:error, {:conflict, "Invitation already processed"}}

      _ ->
        {:error, :forbidden}
    end
  end

  defp parse_role(nil), do: :member
  defp parse_role("owner"), do: :owner
  defp parse_role("admin"), do: :admin
  defp parse_role(_), do: :member
end
