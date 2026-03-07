defmodule SecureSharing.Repo.Migrations.CreateFolders do
  use Ecto.Migration

  def change do
    create table(:folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:folders, type: :binary_id, on_delete: :delete_all)

      # Encrypted folder metadata (name, color, icon, etc.)
      # Encrypted with the folder's KEK
      add :encrypted_metadata, :binary

      # Folder's KEK wrapped by parent folder's KEK
      # For root folders, this is wrapped by owner's PQC public key
      add :wrapped_kek, :binary, null: false

      # KEM ciphertext for decapsulating the shared secret used to wrap KEK
      add :kem_ciphertext, :binary, null: false

      # Direct owner access - KEK wrapped directly by owner's public key
      # Allows owner to always access without traversing hierarchy
      add :owner_wrapped_kek, :binary, null: false
      add :owner_kem_ciphertext, :binary, null: false

      # For server-side operations (not sensitive)
      add :is_root, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Index for listing user's folders
    create index(:folders, [:owner_id])

    # Index for tenant isolation
    create index(:folders, [:tenant_id])

    # Index for folder hierarchy traversal
    create index(:folders, [:parent_id])

    # Ensure only one root folder per user
    create unique_index(:folders, [:owner_id],
             where: "is_root = true",
             name: :folders_owner_root_unique
           )
  end
end
