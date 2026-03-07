defmodule SecureSharingWeb.API.TenantJSON do
  @moduledoc """
  JSON rendering for tenant-related responses.
  """

  alias SecureSharingWeb.Auth.Token

  @doc """
  Renders list of tenants.
  """
  def tenants(%{tenants: tenants}) do
    %{
      data: Enum.map(tenants, &tenant_data/1)
    }
  end

  @doc """
  Renders tenant switch response.
  """
  def switch_tenant(%{
        tenant_id: tenant_id,
        role: role,
        access_token: access_token,
        refresh_token: refresh_token
      }) do
    %{
      data: %{
        current_tenant_id: tenant_id,
        role: to_string(role),
        access_token: access_token,
        refresh_token: refresh_token,
        expires_in: Token.access_token_expiry(),
        token_type: "Bearer"
      }
    }
  end

  @doc """
  Renders tenant configuration.
  """
  def config(%{tenant: tenant}) do
    %{
      data: %{
        id: tenant.id,
        name: tenant.name,
        slug: tenant.slug,
        status: tenant.status,
        plan: tenant.plan,
        pqc_algorithm: tenant.pqc_algorithm,
        storage_quota_bytes: tenant.storage_quota_bytes,
        max_users: tenant.max_users,
        settings: tenant.settings
      }
    }
  end

  # ==================== Member Management ====================

  @doc """
  Renders list of tenant members.
  """
  def members(%{members: members}) do
    %{
      data: Enum.map(members, &member_data/1)
    }
  end

  @doc """
  Renders a single member.
  """
  def member(%{member: member}) do
    %{
      data: member_data(member)
    }
  end

  # ==================== Invitations ====================

  @doc """
  Renders a newly created invitation.
  """
  def invitation(%{invitation: invitation, invitee: invitee}) do
    %{
      data: %{
        id: invitation.id,
        user_id: invitee.id,
        email: invitee.email,
        display_name: invitee.display_name,
        role: to_string(invitation.role),
        status: invitation.status,
        invited_at: invitation.created_at
      }
    }
  end

  @doc """
  Renders list of pending invitations for current user.
  """
  def invitations(%{invitations: invitations}) do
    %{
      data: Enum.map(invitations, &invitation_data/1)
    }
  end

  @doc """
  Renders accepted invitation response.
  """
  def invitation_accepted(%{user_tenant: user_tenant}) do
    %{
      data: %{
        id: user_tenant.id,
        tenant_id: user_tenant.tenant_id,
        role: to_string(user_tenant.role),
        status: user_tenant.status,
        joined_at: user_tenant.updated_at
      }
    }
  end

  # ==================== Private Helpers ====================

  defp tenant_data(tenant) when is_map(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      role: to_string(tenant.role),
      joined_at: tenant[:joined_at]
    }
  end

  defp member_data(member) when is_struct(member) do
    # Handle both UserTenant struct (with preloaded user) and plain maps
    {email, display_name} = get_user_info(member)

    %{
      id: Map.get(member, :id) || member.user_id,
      user_id: member.user_id,
      email: email,
      display_name: display_name,
      role: to_string(member.role),
      status: member.status,
      joined_at: Map.get(member, :joined_at) || Map.get(member, :inserted_at)
    }
  end

  defp member_data(member) when is_map(member) do
    %{
      id: member[:id] || member[:user_id],
      user_id: member[:user_id],
      email: member[:email],
      display_name: member[:display_name],
      role: to_string(member[:role]),
      status: member[:status],
      joined_at: member[:joined_at] || member[:inserted_at]
    }
  end

  # Extract email and display_name from UserTenant with preloaded user or from map
  defp get_user_info(%{user: %{email: email, display_name: display_name}}) do
    {email, display_name}
  end

  defp get_user_info(%{email: email, display_name: display_name}) do
    {email, display_name}
  end

  defp get_user_info(_), do: {nil, nil}

  defp invitation_data(invitation) when is_map(invitation) do
    %{
      id: invitation.id,
      tenant_id: invitation.tenant_id,
      tenant_name: invitation[:tenant_name],
      tenant_slug: invitation[:tenant_slug],
      role: to_string(invitation.role),
      invited_by: %{
        id: invitation[:invited_by_id],
        email: invitation[:invited_by_email],
        display_name: invitation[:invited_by_name]
      },
      invited_at: invitation[:invited_at]
    }
  end
end
