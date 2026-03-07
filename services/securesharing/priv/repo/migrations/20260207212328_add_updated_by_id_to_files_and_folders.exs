defmodule SecureSharing.Repo.Migrations.AddUpdatedByIdToFilesAndFolders do
  use Ecto.Migration

  def change do
    alter table(:files) do
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:folders) do
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:files, [:updated_by_id])
    create index(:folders, [:updated_by_id])
  end
end
