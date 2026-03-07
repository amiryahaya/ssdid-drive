defmodule SecureSharing.Files.Folder do
  @moduledoc """
  Folder schema with KEK (Key Encryption Key) support.

  Each folder has its own KEK that wraps:
  - DEKs of files within the folder
  - KEKs of child folders

  The folder's KEK is wrapped by:
  - Parent folder's KEK (for nested folders)
  - Owner's PQC public key (for root folders)

  Owner always has direct access via owner_wrapped_kek, allowing
  decryption without traversing the folder hierarchy.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.{Tenant, User}

  schema "folders" do
    belongs_to :tenant, Tenant
    belongs_to :owner, User
    belongs_to :parent, __MODULE__
    belongs_to :updated_by, User
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :files, SecureSharing.Files.File

    # Encrypted metadata (name, color, icon) - encrypted with folder's KEK
    field :encrypted_metadata, :binary
    field :metadata_nonce, :binary

    # KEK wrapped by parent's KEK (or owner's PQC PK for root)
    field :wrapped_kek, :binary

    # KEM ciphertext for unwrapping wrapped_kek
    field :kem_ciphertext, :binary

    # Direct owner access - always encrypted with owner's PQC public key
    field :owner_wrapped_kek, :binary
    field :owner_kem_ciphertext, :binary

    # Owner's signature over folder state (creation/update/move)
    field :signature, :binary

    # Server-managed flag
    field :is_root, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new folder.

  Required fields:
  - tenant_id: The tenant this folder belongs to
  - owner_id: The user who owns this folder
  - wrapped_kek: The folder's KEK, wrapped appropriately
  - kem_ciphertext: KEM ciphertext for unwrapping
  - owner_wrapped_kek: KEK wrapped for direct owner access
  - owner_kem_ciphertext: KEM ciphertext for owner access

  Optional fields:
  - parent_id: Parent folder (nil for root)
  - encrypted_metadata: Encrypted folder name/metadata
  - is_root: Whether this is a root folder
  """
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [
      :tenant_id,
      :owner_id,
      :parent_id,
      :encrypted_metadata,
      :metadata_nonce,
      :wrapped_kek,
      :kem_ciphertext,
      :owner_wrapped_kek,
      :owner_kem_ciphertext,
      :signature,
      :is_root
    ])
    |> validate_required([
      :tenant_id,
      :owner_id,
      :wrapped_kek,
      :kem_ciphertext,
      :owner_wrapped_kek,
      :owner_kem_ciphertext
    ])
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:parent_id)
    |> validate_root_folder()
  end

  @doc """
  Changeset for creating a root folder.
  Root folders have no parent and is_root=true.
  """
  def root_changeset(folder, attrs) do
    folder
    |> changeset(Map.merge(attrs, %{is_root: true, parent_id: nil}))
    |> unique_constraint(:owner_id,
      name: :folders_owner_root_unique,
      message: "user already has a root folder"
    )
  end

  @doc """
  Changeset for updating folder metadata.
  Only encrypted_metadata can be updated.
  """
  def metadata_changeset(folder, attrs) do
    folder
    |> cast(attrs, [:encrypted_metadata, :metadata_nonce, :signature, :updated_by_id])
  end

  @doc """
  Changeset for moving a folder to a new parent.
  """
  def move_changeset(folder, attrs) do
    folder
    |> cast(attrs, [:parent_id, :wrapped_kek, :kem_ciphertext, :signature])
    |> validate_required([:parent_id, :wrapped_kek])
    |> foreign_key_constraint(:parent_id)
  end

  # Validates that root folders have no parent
  defp validate_root_folder(changeset) do
    is_root = get_field(changeset, :is_root)
    parent_id = get_field(changeset, :parent_id)

    cond do
      is_root && parent_id != nil ->
        add_error(changeset, :parent_id, "root folder cannot have a parent")

      !is_root && parent_id == nil ->
        add_error(changeset, :parent_id, "non-root folder must have a parent")

      true ->
        changeset
    end
  end
end
