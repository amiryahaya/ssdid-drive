defmodule SecureSharing.Files.File do
  @moduledoc """
  File schema with DEK (Data Encryption Key) support.

  Each file has its own DEK that encrypts:
  - The file content (stored as encrypted blob)
  - The file metadata (filename, mimeType, size, etc.)

  The file's DEK is wrapped by the parent folder's KEK.
  The owner signs the package (encrypted blob hash + wrapped DEK + encrypted metadata)
  to provide integrity and authenticity verification.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.{Tenant, User}
  alias SecureSharing.Files.Folder

  @file_statuses ~w(pending uploading complete failed)

  schema "files" do
    belongs_to :tenant, Tenant
    belongs_to :owner, User
    belongs_to :folder, Folder
    belongs_to :updated_by, User

    # Encrypted metadata (filename, mimeType, size, checksum)
    # Encrypted with file's DEK
    field :encrypted_metadata, :binary

    # DEK wrapped by folder's KEK
    field :wrapped_dek, :binary

    # KEM ciphertext for unwrapping wrapped_dek
    field :kem_ciphertext, :binary

    # Owner's signature over the package
    field :signature, :binary

    # Server-managed (not sensitive)
    field :blob_size, :integer, default: 0
    field :blob_hash, :string
    field :storage_path, :string
    field :chunk_count, :integer, default: 1
    field :status, :string, default: "complete"

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new file.

  Required fields:
  - tenant_id: The tenant this file belongs to
  - owner_id: The user who owns this file
  - folder_id: The parent folder
  - encrypted_metadata: Encrypted filename/metadata
  - wrapped_dek: The file's DEK, wrapped by folder's KEK
  - kem_ciphertext: KEM ciphertext for unwrapping
  - signature: Owner's signature over the package
  - storage_path: Where the encrypted blob is stored

  Optional fields:
  - blob_size: Size of encrypted blob
  - blob_hash: Hash of ciphertext
  - chunk_count: Number of chunks
  - status: Upload status
  """
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :tenant_id,
      :owner_id,
      :folder_id,
      :updated_by_id,
      :encrypted_metadata,
      :wrapped_dek,
      :kem_ciphertext,
      :signature,
      :blob_size,
      :blob_hash,
      :storage_path,
      :chunk_count,
      :status
    ])
    |> validate_required([
      :tenant_id,
      :owner_id,
      # folder_id is optional - nil means root folder
      :encrypted_metadata,
      :wrapped_dek,
      :kem_ciphertext,
      :signature,
      :storage_path
    ])
    |> validate_inclusion(:status, @file_statuses)
    |> validate_number(:blob_size, greater_than_or_equal_to: 0)
    |> validate_number(:chunk_count, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:folder_id)
    |> unique_constraint(:storage_path)
  end

  @doc """
  Changeset for updating file status during upload.
  """
  def status_changeset(file, attrs) do
    file
    |> cast(attrs, [:status, :blob_size, :blob_hash, :chunk_count, :updated_by_id])
    |> validate_inclusion(:status, @file_statuses)
  end

  @doc """
  Changeset for moving a file to a different folder.
  Requires new wrapped_dek and kem_ciphertext (re-wrapped with new folder's KEK).
  """
  def move_changeset(file, attrs) do
    file
    |> cast(attrs, [:folder_id, :wrapped_dek, :kem_ciphertext, :signature])
    |> validate_required([:folder_id, :wrapped_dek, :kem_ciphertext, :signature])
    |> foreign_key_constraint(:folder_id)
  end
end
