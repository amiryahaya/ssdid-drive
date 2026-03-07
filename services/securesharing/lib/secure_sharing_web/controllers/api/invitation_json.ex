defmodule SecureSharingWeb.API.InvitationJSON do
  @moduledoc """
  JSON rendering for authenticated invitation management endpoints.
  """

  @doc """
  Renders a list of invitations with pagination.
  """
  def index(%{invitations: invitations, pagination: pagination}) do
    %{
      data: Enum.map(invitations, &invitation_data/1),
      pagination: pagination
    }
  end

  @doc """
  Renders a single invitation.
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
      token: invitation.token,
      role: invitation.role,
      status: invitation.status,
      message: invitation.message,
      expires_at: invitation.expires_at,
      accepted_at: invitation.accepted_at,
      created_at: invitation.created_at,
      updated_at: invitation.updated_at,
      inviter: inviter_data(invitation.inviter),
      accepted_by: accepted_by_data(invitation.accepted_by)
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
  defp accepted_by_data(%Ecto.Association.NotLoaded{}), do: nil

  defp accepted_by_data(user) do
    %{
      id: user.id,
      display_name: user.display_name || user.email,
      email: user.email
    }
  end
end
