# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :secure_sharing,
  ecto_repos: [SecureSharing.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Oban - Background job processing
config :secure_sharing, Oban,
  repo: SecureSharing.Repo,
  queues: [default: 10, mailers: 5, cleanup: 3, storage: 5, notifications: 10, maintenance: 2]

# OneSignal - Push notifications (cross-platform: Android, iOS, Windows)
# Set ONESIGNAL_APP_ID and ONESIGNAL_API_KEY environment variables in prod
config :secure_sharing, SecureSharing.Notifications.OneSignal,
  app_id: System.get_env("ONESIGNAL_APP_ID"),
  api_key: System.get_env("ONESIGNAL_API_KEY")

# Admin Setup - Bootstrap configuration
# Set ADMIN_SETUP_TOKEN to require a token for the initial admin setup
# Leave unset or empty to allow setup without a token (for development)
config :secure_sharing, :admin_setup, setup_token: System.get_env("ADMIN_SETUP_TOKEN")

# Storage - Blob storage configuration (default: local filesystem for dev)
config :secure_sharing, SecureSharing.Storage,
  provider: SecureSharing.Storage.Providers.Local,
  base_path: "priv/storage"

# Hammer - Rate limiting
# NOTE: ETS backend is for single-node deployments only.
# For clustered/distributed deployments, use Redis backend:
#   backend: {Hammer.Backend.Redis, [
#     expiry_ms: 60_000 * 60 * 4,
#     redix_config: [host: "localhost", port: 6379]
#   ]}
# Or use Hammer.Backend.Mnesia for distributed Erlang clusters.
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# SSDID - Self-Sovereign Distributed Identity configuration
config :secure_sharing,
  ssdid_registry_url: System.get_env("SSDID_REGISTRY_URL", "https://registry.ssdid.my"),
  ssdid_algorithm: :ed25519,
  ssdid_identity_password: System.get_env("SSDID_IDENTITY_PASSWORD", "dev_identity_password_change_in_prod")

# Crypto - Post-quantum cryptography configuration
config :secure_sharing, SecureSharing.Crypto,
  kem_provider: SecureSharing.Crypto.Providers.KazKEM,
  sign_provider: SecureSharing.Crypto.Providers.KazSign,
  security_level: 128

# Swoosh - Email configuration
config :secure_sharing, SecureSharing.Mailer, adapter: Swoosh.Adapters.Local

# Configures the endpoint
config :secure_sharing, SecureSharingWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SecureSharingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SecureSharing.PubSub,
  live_view: [signing_salt: "PmSM8AMU"]

# PromEx - Prometheus metrics
config :secure_sharing, SecureSharing.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: [
    port: 4021,
    path: "/metrics",
    protocol: :http,
    pool_size: 5,
    cowboy_opts: [],
    auth_strategy: :none
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
