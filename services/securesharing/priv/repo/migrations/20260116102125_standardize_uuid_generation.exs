defmodule SecureSharing.Repo.Migrations.StandardizeUuidGeneration do
  @moduledoc """
  Removes DB-level uuidv7() defaults from primary keys.

  UUID generation is now handled exclusively by Ecto using the `uuidv7` library.
  This standardizes all primary key generation at the application level.
  """
  use Ecto.Migration

  def change do
    # Remove uuidv7() default from tenants table
    execute(
      "ALTER TABLE tenants ALTER COLUMN id DROP DEFAULT",
      "ALTER TABLE tenants ALTER COLUMN id SET DEFAULT uuidv7()"
    )

    # Remove uuidv7() default from users table
    execute(
      "ALTER TABLE users ALTER COLUMN id DROP DEFAULT",
      "ALTER TABLE users ALTER COLUMN id SET DEFAULT uuidv7()"
    )

    # Remove uuidv7() default from users_tokens table
    execute(
      "ALTER TABLE users_tokens ALTER COLUMN id DROP DEFAULT",
      "ALTER TABLE users_tokens ALTER COLUMN id SET DEFAULT uuidv7()"
    )
  end
end
