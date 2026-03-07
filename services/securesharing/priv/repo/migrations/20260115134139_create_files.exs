defmodule SecureSharing.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, type: :binary_id, on_delete: :delete_all), null: false

      # Encrypted file metadata (filename, mimeType, size, checksum, etc.)
      # Encrypted with the file's DEK
      add :encrypted_metadata, :binary, null: false

      # File's DEK wrapped by folder's KEK
      add :wrapped_dek, :binary, null: false

      # KEM ciphertext for decapsulating the shared secret used to wrap DEK
      add :kem_ciphertext, :binary, null: false

      # Owner's digital signature over the package
      # Signs: hash of encrypted blob + wrapped DEK + encrypted metadata
      add :signature, :binary, null: false

      # Server-managed metadata (not sensitive - for operations)
      # Size of the encrypted blob (for quota management)
      add :blob_size, :bigint, null: false, default: 0

      # Hash of the ciphertext (for dedup/integrity check)
      add :blob_hash, :string

      # Storage location of the encrypted blob
      # Could be S3 key, local path, etc.
      add :storage_path, :string, null: false

      # Number of chunks (for chunked uploads)
      add :chunk_count, :integer, default: 1

      # Upload status
      add :status, :string, default: "complete", null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Index for listing files in a folder
    create index(:files, [:folder_id])

    # Index for listing user's files
    create index(:files, [:owner_id])

    # Index for tenant isolation
    create index(:files, [:tenant_id])

    # Index for finding files by storage path
    create unique_index(:files, [:storage_path])

    # Index for deduplication by blob hash within tenant
    create index(:files, [:tenant_id, :blob_hash])
  end
end
