defmodule SecureSharingWeb.API.FolderJSON do
  @moduledoc """
  JSON rendering for folder responses.
  """

  alias SecureSharing.Files.Folder
  alias SecureSharing.Accounts.User

  @doc """
  Renders a list of folders with optional pagination metadata.
  """
  def index(%{folders: folders, meta: meta}) do
    %{data: Enum.map(folders, &folder_data/1), meta: meta}
  end

  def index(%{folders: folders}) do
    %{data: Enum.map(folders, &folder_data/1)}
  end

  @doc """
  Renders a single folder.
  """
  def show(%{folder: folder}) do
    %{data: folder_data(folder)}
  end

  defp folder_data(nil), do: nil

  defp folder_data(%Folder{} = folder) do
    owner =
      case folder.owner do
        %User{} = user ->
          %{id: user.id, public_keys: user.public_keys}

        _ ->
          nil
      end

    %{
      id: folder.id,
      parent_id: folder.parent_id,
      owner_id: folder.owner_id,
      updated_by_id: folder.updated_by_id,
      tenant_id: folder.tenant_id,
      is_root: folder.is_root,
      encrypted_metadata: encode_binary(folder.encrypted_metadata),
      metadata_nonce: encode_binary(folder.metadata_nonce),
      wrapped_kek: encode_binary(folder.wrapped_kek),
      kem_ciphertext: encode_binary(folder.kem_ciphertext),
      owner_wrapped_kek: encode_binary(folder.owner_wrapped_kek),
      owner_kem_ciphertext: encode_binary(folder.owner_kem_ciphertext),
      signature: encode_binary(folder.signature),
      owner: owner,
      created_at: folder.created_at,
      updated_at: folder.updated_at
    }
  end

  defp encode_binary(nil), do: nil
  defp encode_binary(data) when is_binary(data), do: Base.encode64(data)
end
