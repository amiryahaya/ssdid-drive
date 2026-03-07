defmodule SecureSharingWeb.API.InviteJSON do
  @moduledoc """
  JSON rendering for invitation endpoints.
  """

  alias SecureSharing.Accounts.User
  alias SecureSharingWeb.Auth.Token

  @doc """
  Renders invitation info for the acceptance screen.
  """
  def info(%{invitation: invitation}) do
    %{
      data: invitation_info(invitation)
    }
  end

  defp invitation_info(%{valid: false, error_reason: error_reason}) do
    %{
      valid: false,
      error_reason: error_reason
    }
  end

  defp invitation_info(invitation) do
    %{
      id: invitation[:id],
      email: invitation[:email],
      role: invitation[:role],
      tenant_name: invitation[:tenant_name],
      inviter_name: invitation[:inviter_name],
      message: invitation[:message],
      expires_at: invitation[:expires_at],
      valid: invitation[:valid],
      error_reason: invitation[:error_reason]
    }
  end

  @doc """
  Renders successful invitation acceptance response.
  """
  def accept(%{user: user, role: role, access_token: access_token, refresh_token: refresh_token}) do
    %{
      data: %{
        user: user_data(user, role),
        access_token: access_token,
        refresh_token: refresh_token,
        expires_in: Token.access_token_expiry(),
        token_type: "Bearer"
      }
    }
  end

  defp user_data(%User{} = user, role) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      tenant_id: user.tenant_id,
      role: role,
      status: user.status,
      created_at: user.created_at
    }
  end

  @doc """
  Renders a list of invitations (for admin endpoints).
  """
  def index(%{invitations: invitations, pagination: pagination}) do
    %{
      data: Enum.map(invitations, &invitation_data/1),
      pagination: pagination
    }
  end

  def index(%{invitations: invitations}) do
    %{
      data: Enum.map(invitations, &invitation_data/1)
    }
  end

  @doc """
  Renders a single invitation (for admin endpoints).
  """
  def show(%{invitation: invitation}) do
    %{
      data: invitation_data(invitation)
    }
  end

  @doc """
  Renders invitation creation response.
  """
  def create(%{invitation: invitation}) do
    %{
      data: invitation_data(invitation)
    }
  end

  defp invitation_data(invitation) do
    %{
      id: invitation.id,
      email: invitation.email,
      role: invitation.role,
      status: invitation.status,
      message: invitation.message,
      expires_at: invitation.expires_at,
      accepted_at: invitation.accepted_at,
      created_at: invitation.created_at,
      inviter: inviter_data(invitation.inviter),
      accepted_by: if(invitation.accepted_by, do: accepted_by_data(invitation.accepted_by))
    }
  end

  defp inviter_data(nil), do: nil

  defp inviter_data(inviter) do
    %{
      id: inviter.id,
      display_name: inviter.display_name || inviter.email,
      email: inviter.email
    }
  end

  defp accepted_by_data(nil), do: nil

  defp accepted_by_data(user) do
    %{
      id: user.id,
      display_name: user.display_name || user.email,
      email: user.email
    }
  end
end
