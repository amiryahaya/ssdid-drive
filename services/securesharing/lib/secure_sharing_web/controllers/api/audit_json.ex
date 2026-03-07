defmodule SecureSharingWeb.API.AuditJSON do
  @moduledoc """
  JSON rendering for audit events.
  """

  def index(%{events: events, meta: meta}) do
    %{data: Enum.map(events, &event_data/1), meta: meta}
  end

  defp event_data(event) do
    %{
      id: event.id,
      action: event.action,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      user_id: event.user_id,
      user_email: if(Ecto.assoc_loaded?(event.user) && event.user, do: event.user.email),
      ip_address: event.ip_address,
      user_agent: event.user_agent,
      status: event.status,
      error_message: event.error_message,
      metadata: event.metadata,
      inserted_at: event.inserted_at
    }
  end
end
