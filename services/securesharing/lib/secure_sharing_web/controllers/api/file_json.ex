defmodule SecureSharingWeb.API.FileJSON do
  @moduledoc """
  JSON rendering for file responses.
  """

  alias SecureSharing.Files.File

  @doc """
  Renders a list of files with optional pagination metadata.
  """
  def index(%{files: files, meta: meta}) do
    %{data: Enum.map(files, &file_data/1), meta: meta}
  end

  def index(%{files: files}) do
    %{data: Enum.map(files, &file_data/1)}
  end

  @doc """
  Renders a single file.
  """
  def show(%{file: file}) do
    %{data: file_data(file)}
  end

  @doc """
  Renders upload URL response.
  """
  def upload_url(%{file: file, upload_url: url}) do
    %{
      data: %{
        file_id: file.id,
        upload_url: url,
        storage_path: file.storage_path,
        expires_in: 3600
      }
    }
  end

  @doc """
  Renders download URL response.
  """
  def download_url(%{file: file, download_url: url}) do
    %{
      data: %{
        file_id: file.id,
        download_url: url,
        expires_in: 3600
      }
    }
  end

  defp file_data(%File{} = file) do
    %{
      id: file.id,
      folder_id: file.folder_id,
      owner_id: file.owner_id,
      updated_by_id: file.updated_by_id,
      tenant_id: file.tenant_id,
      encrypted_metadata: encode_binary(file.encrypted_metadata),
      wrapped_dek: encode_binary(file.wrapped_dek),
      kem_ciphertext: encode_binary(file.kem_ciphertext),
      signature: encode_binary(file.signature),
      blob_size: file.blob_size,
      blob_hash: file.blob_hash,
      storage_path: file.storage_path,
      chunk_count: file.chunk_count,
      status: file.status,
      created_at: file.created_at,
      updated_at: file.updated_at
    }
  end

  defp encode_binary(nil), do: nil
  defp encode_binary(data) when is_binary(data), do: Base.encode64(data)
end
