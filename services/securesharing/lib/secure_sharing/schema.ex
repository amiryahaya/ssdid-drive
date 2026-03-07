defmodule SecureSharing.Schema do
  @moduledoc """
  Base schema configuration for SecureSharing.

  Provides consistent defaults across all schemas:
  - UUIDv7 primary keys (time-ordered, sortable)
  - Canonical timestamp columns (created_at/updated_at with TIMESTAMPTZ)

  ## Usage

      defmodule SecureSharing.Accounts.User do
        use SecureSharing.Schema

        schema "users" do
          field :email, :string
          # ...
          timestamps()
        end
      end

  ## Timestamp Behavior

  Timestamps are configured to match the canonical database schema:
  - `created_at` instead of Ecto's default `inserted_at`
  - Type `:utc_datetime_usec` maps to TIMESTAMPTZ in PostgreSQL
  - Database triggers auto-update `updated_at` on row modification

  For tables without `updated_at` (like credentials), use:

      timestamps(updated_at: false)
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type UUIDv7
      @timestamps_opts [
        inserted_at: :created_at,
        type: :utc_datetime_usec
      ]
    end
  end
end
