defmodule SecureSharing.Repo.Migrations.AlignTimestampsWithCanonicalSchema do
  @moduledoc """
  Aligns timestamp columns with the canonical schema (02-database-schema.md).

  Changes:
  1. Renames `inserted_at` → `created_at` on all tables
  2. Converts timestamp columns to TIMESTAMPTZ (with timezone)
  3. Adds DB defaults (NOW()) to timestamp columns
  4. Creates `update_updated_at()` trigger function
  5. Adds triggers to auto-update `updated_at` on each table

  This ensures timestamps are:
  - Database-managed (not application-dependent)
  - Timezone-aware (TIMESTAMPTZ stores in UTC, displays in session TZ)
  - Automatically updated on row modification
  """
  use Ecto.Migration

  # Tables with both created_at and updated_at
  @tables_with_updated_at [
    :tenants,
    :users,
    :folders,
    :files,
    :share_grants,
    :recovery_configs,
    :recovery_shares,
    :recovery_requests,
    :recovery_approvals,
    :idp_configs
  ]

  # Tables with only created_at (no updated_at)
  @tables_created_at_only [
    :users_tokens,
    :credentials
  ]

  def up do
    # 1. Create the trigger function for auto-updating updated_at
    execute("""
    CREATE OR REPLACE FUNCTION update_updated_at()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    # 2. Migrate tables with both timestamps
    for table <- @tables_with_updated_at do
      # Rename inserted_at → created_at
      execute("ALTER TABLE #{table} RENAME COLUMN inserted_at TO created_at")

      # Convert to TIMESTAMPTZ and add defaults
      execute("""
      ALTER TABLE #{table}
        ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
        ALTER COLUMN created_at SET DEFAULT NOW(),
        ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC',
        ALTER COLUMN updated_at SET DEFAULT NOW()
      """)

      # Create trigger for auto-updating updated_at
      execute("""
      CREATE TRIGGER #{table}_updated_at
        BEFORE UPDATE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION update_updated_at()
      """)
    end

    # 3. Migrate tables with only created_at
    for table <- @tables_created_at_only do
      # Rename inserted_at → created_at
      execute("ALTER TABLE #{table} RENAME COLUMN inserted_at TO created_at")

      # Convert to TIMESTAMPTZ and add default
      execute("""
      ALTER TABLE #{table}
        ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
        ALTER COLUMN created_at SET DEFAULT NOW()
      """)
    end
  end

  def down do
    # Reverse: tables with only created_at
    for table <- @tables_created_at_only do
      execute("""
      ALTER TABLE #{table}
        ALTER COLUMN created_at TYPE TIMESTAMP WITHOUT TIME ZONE,
        ALTER COLUMN created_at DROP DEFAULT
      """)

      execute("ALTER TABLE #{table} RENAME COLUMN created_at TO inserted_at")
    end

    # Reverse: tables with both timestamps
    for table <- @tables_with_updated_at do
      # Drop trigger
      execute("DROP TRIGGER IF EXISTS #{table}_updated_at ON #{table}")

      # Convert back to timestamp without TZ and drop defaults
      execute("""
      ALTER TABLE #{table}
        ALTER COLUMN created_at TYPE TIMESTAMP WITHOUT TIME ZONE,
        ALTER COLUMN created_at DROP DEFAULT,
        ALTER COLUMN updated_at TYPE TIMESTAMP WITHOUT TIME ZONE,
        ALTER COLUMN updated_at DROP DEFAULT
      """)

      # Rename created_at → inserted_at
      execute("ALTER TABLE #{table} RENAME COLUMN created_at TO inserted_at")
    end

    # Drop the trigger function
    execute("DROP FUNCTION IF EXISTS update_updated_at()")
  end
end
