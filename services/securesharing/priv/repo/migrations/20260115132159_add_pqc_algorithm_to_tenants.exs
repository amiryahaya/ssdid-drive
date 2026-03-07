defmodule SecureSharing.Repo.Migrations.AddPqcAlgorithmToTenants do
  use Ecto.Migration

  def change do
    # Create enum type for PQC algorithm suites
    execute(
      "CREATE TYPE pqc_algorithm AS ENUM ('kaz', 'nist', 'hybrid')",
      "DROP TYPE pqc_algorithm"
    )

    alter table(:tenants) do
      # kaz = KAZ-KEM + KAZ-SIGN (Malaysian algorithms)
      # nist = ML-KEM + ML-DSA (NIST FIPS 203/204)
      # hybrid = Both KAZ and NIST combined for defense in depth
      add :pqc_algorithm, :pqc_algorithm, null: false, default: "kaz"
    end

    # Index for filtering tenants by algorithm
    create index(:tenants, [:pqc_algorithm])
  end
end
