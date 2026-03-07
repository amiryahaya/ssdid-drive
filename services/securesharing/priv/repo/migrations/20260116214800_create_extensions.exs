defmodule SecureSharing.Repo.Migrations.CreateExtensions do
  @moduledoc """
  Creates required PostgreSQL extensions.

  - pgcrypto: Cryptographic functions
  - pg_trgm: Trigram search (optional, for fuzzy matching)
  """
  use Ecto.Migration

  def change do
    # pgcrypto for cryptographic functions
    execute(
      "CREATE EXTENSION IF NOT EXISTS pgcrypto",
      "DROP EXTENSION IF EXISTS pgcrypto"
    )

    # pg_trgm for trigram-based similarity search (optional)
    execute(
      "CREATE EXTENSION IF NOT EXISTS pg_trgm",
      "DROP EXTENSION IF EXISTS pg_trgm"
    )
  end
end
