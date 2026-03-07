defmodule SecureSharing.Repo.Migrations.AddFolderSignatureFields do
  use Ecto.Migration

  def change do
    alter table(:folders) do
      add :metadata_nonce, :binary
      add :signature, :binary
    end
  end
end
