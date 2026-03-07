defmodule SecureSharingWeb.API.RecoveryJSON do
  @moduledoc """
  JSON rendering for recovery responses.
  """

  alias SecureSharing.Recovery.{RecoveryConfig, RecoveryShare, RecoveryRequest, RecoveryApproval}

  @doc """
  Renders recovery configuration.
  """
  def config(%{config: nil}) do
    %{data: nil}
  end

  def config(%{config: config}) do
    %{data: config_data(config)}
  end

  @doc """
  Renders a list of recovery shares.
  """
  def shares(%{shares: shares}) do
    %{data: Enum.map(shares, &share_data/1)}
  end

  @doc """
  Renders a single recovery share.
  """
  def share(%{share: share}) do
    %{data: share_data(share)}
  end

  @doc """
  Renders a list of recovery requests.
  """
  def requests(%{requests: requests}) do
    %{data: Enum.map(requests, &request_data/1)}
  end

  @doc """
  Renders a single recovery request.
  """
  def request(%{request: request}) do
    %{data: request_data(request)}
  end

  @doc """
  Renders a recovery request with progress.
  """
  def request_detail(%{request: request, progress: progress}) do
    %{
      data:
        request_data(request)
        |> Map.put(:progress, %{
          approvals: progress.approvals,
          threshold: progress.threshold,
          total_shares: progress.total_shares,
          percentage: progress.percentage
        })
    }
  end

  @doc """
  Renders a recovery approval.
  """
  def approval(%{approval: approval}) do
    %{data: approval_data(approval)}
  end

  @doc """
  Renders recovery completion response.
  """
  def complete(%{user: user}) do
    %{
      data: %{
        message: "Recovery completed successfully",
        user_id: user.id,
        status: user.status
      }
    }
  end

  # Data helpers

  defp config_data(%RecoveryConfig{} = config) do
    %{
      id: config.id,
      user_id: config.user_id,
      threshold: config.threshold,
      total_shares: config.total_shares,
      setup_complete: config.setup_complete,
      last_verified_at: config.last_verified_at,
      created_at: config.created_at,
      updated_at: config.updated_at
    }
  end

  defp share_data(%RecoveryShare{} = share) do
    %{
      id: share.id,
      config_id: share.config_id,
      owner_id: share.owner_id,
      trustee_id: share.trustee_id,
      share_index: share.share_index,
      encrypted_share: encode_binary(share.encrypted_share),
      kem_ciphertext: encode_binary(share.kem_ciphertext),
      signature: encode_binary(share.signature),
      accepted: share.accepted,
      accepted_at: share.accepted_at,
      created_at: share.created_at,
      updated_at: share.updated_at
    }
  end

  defp request_data(%RecoveryRequest{} = request) do
    %{
      id: request.id,
      config_id: request.config_id,
      user_id: request.user_id,
      verified_by_id: request.verified_by_id,
      new_public_key: encode_binary(request.new_public_key),
      reason: request.reason,
      status: request.status,
      verified_at: request.verified_at,
      expires_at: request.expires_at,
      completed_at: request.completed_at,
      created_at: request.created_at,
      updated_at: request.updated_at
    }
  end

  defp approval_data(%RecoveryApproval{} = approval) do
    %{
      id: approval.id,
      request_id: approval.request_id,
      share_id: approval.share_id,
      trustee_id: approval.trustee_id,
      reencrypted_share: encode_binary(approval.reencrypted_share),
      kem_ciphertext: encode_binary(approval.kem_ciphertext),
      signature: encode_binary(approval.signature),
      created_at: approval.created_at,
      updated_at: approval.updated_at
    }
  end

  defp encode_binary(nil), do: nil
  defp encode_binary(data) when is_binary(data), do: Base.encode64(data)
end
