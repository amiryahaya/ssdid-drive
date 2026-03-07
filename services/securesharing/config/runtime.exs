import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/secure_sharing start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :secure_sharing, SecureSharingWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Storage - S3 configuration for production
  s3_bucket = System.get_env("S3_BUCKET")

  if s3_bucket do
    config :secure_sharing, SecureSharing.Storage,
      provider: SecureSharing.Storage.Providers.S3,
      bucket: s3_bucket,
      region: System.get_env("AWS_REGION", "us-east-1")

    config :ex_aws,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "us-east-1")

    # For S3-compatible services (MinIO, Garage), uncomment:
    # config :ex_aws, :s3,
    #   scheme: System.get_env("S3_SCHEME", "https://"),
    #   host: System.get_env("S3_HOST"),
    #   port: String.to_integer(System.get_env("S3_PORT", "443"))
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :secure_sharing, SecureSharing.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Clustering configuration
  # See SecureSharing.Cluster module for supported strategies:
  # - dns: DNS-based discovery (default, for K8s headless services, Fly.io)
  # - kubernetes: Native K8s API discovery
  # - gossip: UDP gossip protocol (for development/simple deployments)
  # - epmd: Static node list
  # - none: Disable clustering
  #
  # Set CLUSTER_STRATEGY to choose (default: "dns")
  # Set DNS_CLUSTER_QUERY for DNS strategy (e.g., "secure-sharing.internal")
  # Set KUBERNETES_SELECTOR for K8s strategy (e.g., "app=secure-sharing")
  # Set GOSSIP_SECRET for gossip strategy
  # Set CLUSTER_NODES for EPMD strategy (comma-separated)
  config :secure_sharing, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Redis configuration for distributed rate limiting
  # Required when running multiple nodes to share rate limit state
  redis_url = System.get_env("REDIS_URL")

  if redis_url do
    config :hammer,
      backend:
        {Hammer.Backend.Redis,
         [
           # 2 hours
           expiry_ms: 60_000 * 60 * 2,
           redix_config: [url: redis_url],
           pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE") || "5"),
           pool_max_overflow: 2
         ]}
  end

  # Database pool configuration for clustered deployments
  # Enable multiple pools when running on machines with several cores
  pool_count = String.to_integer(System.get_env("POOL_COUNT") || "1")

  if pool_count > 1 do
    config :secure_sharing, SecureSharing.Repo, pool_count: pool_count
  end

  config :secure_sharing, SecureSharingWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Configure Oban for production
  # Use PostgreSQL notifications for distributed job coordination
  config :secure_sharing, Oban,
    repo: SecureSharing.Repo,
    queues: [
      default: String.to_integer(System.get_env("OBAN_DEFAULT_QUEUE_SIZE") || "10"),
      mailers: String.to_integer(System.get_env("OBAN_MAILER_QUEUE_SIZE") || "5"),
      cleanup: String.to_integer(System.get_env("OBAN_CLEANUP_QUEUE_SIZE") || "3"),
      storage: String.to_integer(System.get_env("OBAN_STORAGE_QUEUE_SIZE") || "5"),
      maintenance: String.to_integer(System.get_env("OBAN_MAINTENANCE_QUEUE_SIZE") || "2")
    ],
    plugins: [
      # Prune jobs older than 7 days
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
      {Oban.Plugins.Cron,
       crontab: [
         # Expire old invitations every hour
         {"0 * * * *", SecureSharing.Workers.ExpireInvitationsWorker},
         # Expire stale share grants every 15 minutes
         {"*/15 * * * *", SecureSharing.Workers.ExpireSharesWorker}
       ]}
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :secure_sharing, SecureSharingWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :secure_sharing, SecureSharingWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
