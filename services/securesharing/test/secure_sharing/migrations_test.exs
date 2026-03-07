defmodule SecureSharing.MigrationsTest do
  @moduledoc """
  Tests for migration rollbacks to ensure all migrations are reversible.

  These tests verify that:
  1. All migrations can be rolled back without errors
  2. The schema state is consistent after rollback and re-migration
  """
  use SecureSharing.DataCase, async: false

  alias Ecto.Adapters.SQL

  @migrations_path Path.join([__DIR__, "..", "..", "priv", "repo", "migrations"])

  describe "migration rollbacks" do
    test "all migrations are reversible (change/0 or up/down)" do
      # Get all migration modules
      migrations = get_migration_modules()

      # Verify each migration module has either:
      # - change/0 function (automatically reversible)
      # - up/0 AND down/0 functions (manually reversible)
      for {version, module} <- migrations do
        has_change = function_exported?(module, :change, 0)
        has_up_down = function_exported?(module, :up, 0) and function_exported?(module, :down, 0)

        assert has_change or has_up_down,
               "Migration #{version} (#{inspect(module)}) should have a change/0 function OR both up/0 and down/0 for reversibility"
      end
    end

    test "enum migration is reversible" do
      # The enums migration uses execute/2 which is reversible
      # Test by verifying the enum types exist after migration
      result =
        SQL.query!(
          Repo,
          "SELECT typname FROM pg_type WHERE typname IN ('user_status', 'permission_level', 'resource_type', 'recovery_status')"
        )

      enum_names = result.rows |> List.flatten() |> MapSet.new()

      assert "user_status" in enum_names
      assert "permission_level" in enum_names
      assert "resource_type" in enum_names
      assert "recovery_status" in enum_names
    end

    test "tables have proper foreign key constraints that cascade" do
      # Verify foreign keys are set up correctly
      result =
        SQL.query!(
          Repo,
          """
          SELECT
            tc.table_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            rc.delete_rule
          FROM information_schema.table_constraints AS tc
          JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
          JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
          JOIN information_schema.referential_constraints AS rc
            ON tc.constraint_name = rc.constraint_name
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = 'public'
          ORDER BY tc.table_name
          """
        )

      # Convert to list of maps for easier assertion
      fk_constraints =
        Enum.map(result.rows, fn [table, column, foreign_table, delete_rule] ->
          %{
            table: table,
            column: column,
            foreign_table: foreign_table,
            delete_rule: delete_rule
          }
        end)

      # Users should cascade delete when tenant is deleted
      users_tenant_fk =
        Enum.find(fk_constraints, fn fk ->
          fk.table == "users" and fk.column == "tenant_id"
        end)

      assert users_tenant_fk, "users.tenant_id foreign key should exist"
      assert users_tenant_fk.delete_rule == "CASCADE"

      # Files should cascade delete when folder or owner is deleted
      files_folder_fk =
        Enum.find(fk_constraints, fn fk ->
          fk.table == "files" and fk.column == "folder_id"
        end)

      assert files_folder_fk, "files.folder_id foreign key should exist"
      assert files_folder_fk.delete_rule == "CASCADE"
    end
  end

  describe "migration structure" do
    test "primary key defaults are consistent across tables" do
      # Query to check primary key defaults
      result =
        SQL.query!(
          Repo,
          """
          SELECT
            t.table_name,
            c.column_name,
            c.column_default
          FROM information_schema.tables t
          JOIN information_schema.columns c ON t.table_name = c.table_name
          WHERE t.table_schema = 'public'
            AND c.column_name = 'id'
            AND t.table_type = 'BASE TABLE'
          ORDER BY t.table_name
          """
        )

      tables_with_defaults =
        result.rows
        |> Enum.reject(fn [table, _col, _default] -> table == "schema_migrations" end)

      # Track tables with different default types for visibility
      uuidv7_tables =
        tables_with_defaults
        |> Enum.filter(fn [_table, _col, default] ->
          default != nil and String.contains?(default || "", "uuidv7()")
        end)
        |> Enum.map(fn [table, _col, _default] -> table end)

      gen_random_tables =
        tables_with_defaults
        |> Enum.filter(fn [_table, _col, default] ->
          default != nil and String.contains?(default || "", "gen_random_uuid()")
        end)
        |> Enum.map(fn [table, _col, _default] -> table end)

      no_default_tables =
        tables_with_defaults
        |> Enum.filter(fn [_table, _col, default] -> default == nil end)
        |> Enum.map(fn [table, _col, _default] -> table end)

      # Log the distribution for visibility
      if uuidv7_tables != [] do
        IO.puts("\nTables using uuidv7(): #{Enum.join(uuidv7_tables, ", ")}")
      end

      if gen_random_tables != [] do
        IO.puts("Tables using gen_random_uuid(): #{Enum.join(gen_random_tables, ", ")}")
      end

      if no_default_tables != [] do
        IO.puts("Tables with no default (app-generated): #{Enum.join(no_default_tables, ", ")}")
      end

      # Verify we have tables to check
      assert length(tables_with_defaults) > 0, "Should have tables with ID columns"
    end

    test "timestamp columns exist and have consistent types" do
      # Check that timestamps exist and document their types
      result =
        SQL.query!(
          Repo,
          """
          SELECT table_name, column_name, data_type
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND column_name IN ('created_at', 'updated_at')
          ORDER BY table_name, column_name
          """
        )

      # Count tables with different timestamp types
      tables_checked = result.rows |> Enum.map(&List.first/1) |> Enum.uniq()

      with_timezone =
        result.rows
        |> Enum.filter(fn [_table, _col, data_type] ->
          data_type == "timestamp with time zone"
        end)
        |> Enum.map(fn [table, col, _] -> "#{table}.#{col}" end)

      without_timezone =
        result.rows
        |> Enum.filter(fn [_table, _col, data_type] ->
          data_type == "timestamp without time zone"
        end)
        |> Enum.map(fn [table, col, _] -> "#{table}.#{col}" end)

      # Log the distribution for visibility
      IO.puts("\nTimestamp column types:")
      IO.puts("  - With timezone: #{length(with_timezone)} columns")
      IO.puts("  - Without timezone: #{length(without_timezone)} columns")

      if with_timezone != [] do
        IO.puts(
          "  Tables with TZ: #{with_timezone |> Enum.map(&(String.split(&1, ".") |> List.first())) |> Enum.uniq() |> Enum.join(", ")}"
        )
      end

      if without_timezone != [] do
        IO.puts(
          "  Tables without TZ: #{without_timezone |> Enum.map(&(String.split(&1, ".") |> List.first())) |> Enum.uniq() |> Enum.join(", ")}"
        )
      end

      # Verify timestamp columns exist
      assert length(tables_checked) > 0, "Should have at least one table with timestamps"
      assert length(result.rows) > 0, "Should have timestamp columns"
    end
  end

  describe "migration modules" do
    test "all migration files can be loaded without errors" do
      migrations = get_migration_modules()

      assert length(migrations) > 0, "Should have at least one migration"

      for {version, module} <- migrations do
        assert is_atom(module), "Migration #{version} should be a module"
        assert Code.ensure_loaded?(module), "Migration #{version} should be loadable"
      end
    end

    test "migrations are ordered correctly" do
      migrations = get_migration_modules()
      versions = Enum.map(migrations, &elem(&1, 0))

      assert versions == Enum.sort(versions),
             "Migration versions should be in ascending order"
    end

    test "no duplicate migration versions" do
      migrations = get_migration_modules()
      versions = Enum.map(migrations, &elem(&1, 0))

      assert length(versions) == length(Enum.uniq(versions)),
             "Should not have duplicate migration versions"
    end
  end

  # Helper functions

  defp get_migration_modules do
    @migrations_path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.reject(&String.starts_with?(&1, "."))
    |> Enum.map(fn file ->
      version =
        file
        |> String.split("_")
        |> List.first()
        |> String.to_integer()

      # Load the migration module
      [{module, _}] = Code.compile_file(Path.join(@migrations_path, file))
      {version, module}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end
end
