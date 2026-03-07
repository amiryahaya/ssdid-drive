defmodule SecureSharing.Release do
  @moduledoc """
  Tasks for production releases.

  Used by the `bin/migrate` script in releases to run migrations
  without Mix or other build tools.

  ## Usage

      # Run migrations
      bin/secure_sharing eval "SecureSharing.Release.migrate()"

      # Rollback the last migration
      bin/secure_sharing eval "SecureSharing.Release.rollback(SecureSharing.Repo, 1)"

      # Create the database (if needed)
      bin/secure_sharing eval "SecureSharing.Release.create()"
  """

  @app :secure_sharing

  @doc """
  Runs all pending migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls back the given number of migrations.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates the database for all repositories.
  """
  def create do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> IO.puts("Database created for #{inspect(repo)}")
        {:error, :already_up} -> IO.puts("Database already exists for #{inspect(repo)}")
        {:error, term} -> raise "Could not create database: #{inspect(term)}"
      end
    end
  end

  @doc """
  Drops the database for all repositories.
  """
  def drop do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_down(repo.config()) do
        :ok -> IO.puts("Database dropped for #{inspect(repo)}")
        {:error, :already_down} -> IO.puts("Database already dropped for #{inspect(repo)}")
        {:error, term} -> raise "Could not drop database: #{inspect(term)}"
      end
    end
  end

  @doc """
  Prints the current migration status.
  """
  def migration_status do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          IO.puts("Migration status for #{inspect(repo)}:")

          migrations = Ecto.Migrator.migrations(repo)

          Enum.each(migrations, fn {status, version, name} ->
            IO.puts("  #{status}: #{version} #{name}")
          end)
        end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
