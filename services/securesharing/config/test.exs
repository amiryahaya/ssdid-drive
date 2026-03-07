import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# DATABASE_URL takes precedence if set (for CI environments)
database_url = System.get_env("DATABASE_URL")

if database_url do
  config :secure_sharing, SecureSharing.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :secure_sharing, SecureSharing.Repo,
    username: "securesharing",
    password: "securesharing_dev",
    hostname: "localhost",
    port: 5433,
    database: "securesharing_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :secure_sharing, SecureSharingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JdQa1NtZ2eDNds9KGoLyd2BHyJJSlnqjeC/C5m21YppMdimnve7mSWo6so4v+unf",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable Oban job execution during tests - use :manual to just track jobs
# Use :inline when you want jobs to actually execute synchronously
config :secure_sharing, Oban, testing: :manual

# Disable rate limiting during tests
config :secure_sharing, :rate_limit_enabled, false

# WebAuthn configuration for tests
config :secure_sharing, :webauthn_origin, "http://localhost:4002"

# Storage - Use local filesystem for tests with isolated directory
config :secure_sharing, SecureSharing.Storage,
  provider: SecureSharing.Storage.Providers.Local,
  base_path: "tmp/test_storage"

# Disable PromEx metrics server during tests (requires Plug.Cowboy which we don't use)
config :secure_sharing, SecureSharing.PromEx,
  disabled: true,
  metrics_server: :disabled

# PII Service - Disabled during tests
config :secure_sharing, SecureSharing.PiiService.Client,
  base_url: "http://localhost:4001",
  enabled: false,
  timeout_ms: 5_000

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
