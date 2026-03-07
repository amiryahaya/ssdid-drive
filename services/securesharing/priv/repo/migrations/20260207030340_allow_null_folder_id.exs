defmodule SecureSharing.Repo.Migrations.AllowNullFolderId do
  use Ecto.Migration

  def change do
    # Allow null folder_id for root folder file uploads
    # Use execute for ALTER COLUMN since we're only changing NULL constraint
    execute "ALTER TABLE files ALTER COLUMN folder_id DROP NOT NULL",
            "ALTER TABLE files ALTER COLUMN folder_id SET NOT NULL"
  end
end
