defmodule SecureSharingWeb.API.ShareJSON do
  @moduledoc """
  JSON rendering for share responses.
  """

  alias SecureSharing.Sharing.ShareGrant

  @doc """
  Renders a list of shares.
  """
  def index(%{shares: shares}) do
    %{data: Enum.map(shares, &share_data/1)}
  end

  @doc """
  Renders a single share.
  """
  def show(%{share: share}) do
    %{data: share_data(share)}
  end

  defp share_data(%ShareGrant{} = share) do
    %{
      id: share.id,
      resource_type: share.resource_type,
      resource_id: share.resource_id,
      grantor_id: share.grantor_id,
      grantee_id: share.grantee_id,
      permission: share.permission,
      recursive: share.recursive,
      algorithm: share.algorithm,
      wrapped_key: encode_binary(share.wrapped_key),
      kem_ciphertext: encode_binary(share.kem_ciphertext),
      signature: encode_binary(share.signature),
      expires_at: share.expires_at,
      revoked_at: share.revoked_at,
      revoked_by_id: share.revoked_by_id,
      active: is_active?(share),
      created_at: share.created_at,
      updated_at: share.updated_at
    }
  end

  defp is_active?(share) do
    is_nil(share.revoked_at) and
      (is_nil(share.expires_at) or DateTime.compare(share.expires_at, DateTime.utc_now()) == :gt)
  end

  defp encode_binary(nil), do: nil
  defp encode_binary(data) when is_binary(data), do: Base.encode64(data)
end
