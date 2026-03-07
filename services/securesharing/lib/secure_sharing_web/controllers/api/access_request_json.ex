defmodule SecureSharingWeb.API.AccessRequestJSON do
  @moduledoc """
  JSON rendering for access request responses.
  """

  def index(%{access_requests: requests}) do
    %{data: Enum.map(requests, &request_data/1)}
  end

  def show(%{access_request: request}) do
    %{data: request_data(request)}
  end

  defp request_data(request) do
    %{
      id: request.id,
      share_grant_id: request.share_grant_id,
      requester_id: request.requester_id,
      requested_permission: request.requested_permission,
      status: request.status,
      reason: request.reason,
      decided_by_id: request.decided_by_id,
      decided_at: request.decided_at,
      created_at: request.created_at
    }
  end
end
