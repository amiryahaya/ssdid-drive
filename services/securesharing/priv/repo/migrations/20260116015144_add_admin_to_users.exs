defmodule SecureSharing.Repo.Migrations.AddAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end

    # Create index for admin queries
    create index(:users, [:is_admin])
  end
end
