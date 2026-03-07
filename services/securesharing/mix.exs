defmodule SecureSharing.MixProject do
  use Mix.Project

  def project do
    [
      app: :secure_sharing,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader],

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {SecureSharing.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Release configuration for production deployments.
  defp releases do
    [
      secure_sharing: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},

      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:uuidv7, "~> 1.0"},

      # SSDID — Self-Sovereign Distributed Identity (pure DID-based auth)
      {:ssdid_server_sdk, path: "../../../SSDID/src/ssdid_server_sdk"},

      # Email
      {:swoosh, "~> 1.17"},
      {:phoenix_swoosh, "~> 1.2"},

      # Background Jobs
      {:oban, "~> 2.18"},

      # AWS/S3
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.18"},
      {:sweet_xml, "~> 0.7"},

      # Rate Limiting
      {:hammer, "~> 6.2"},

      # CORS
      {:corsica, "~> 2.1"},

      # HTTP Client
      {:req, "~> 0.5"},

      # Telemetry & Monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:prom_ex, "~> 1.9"},
      {:logger_json, "~> 6.0"},

      # Utilities
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Clustering
      {:libcluster, "~> 3.4"},

      # Distributed Rate Limiting (Redis backend for Hammer)
      {:hammer_backend_redis, "~> 6.1"},
      {:redix, "~> 1.5"},

      # Dev/Test
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:mox, "~> 1.2", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # PQC Crypto (Malaysian KAZ algorithms)
      {:kaz_kem, path: "native/kaz_kem"},
      {:kaz_sign, path: "native/kaz_sign"},

      # PQC Crypto (NIST ML-KEM/ML-DSA algorithms)
      {:ml_kem, path: "native/ml_kem"},
      {:ml_dsa, path: "native/ml_dsa"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      coverage: ["coveralls.html"]
    ]
  end
end
