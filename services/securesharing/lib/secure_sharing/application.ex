defmodule SecureSharing.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize storage provider (S3, Local, etc.)
    :ok = SecureSharing.Storage.init()

    # Initialize SSDID server identity (must happen before supervisor starts)
    {:ok, _identity} = SecureSharing.Ssdid.init()

    children =
      [
        SecureSharingWeb.Telemetry,
        SecureSharing.PromEx,
        SecureSharing.Repo,
        # Clustering - use libcluster for advanced strategies, DNSCluster as fallback
        cluster_supervisor(),
        {Phoenix.PubSub, name: SecureSharing.PubSub},
        # ETS-based cache for users, tenants, and public keys
        SecureSharing.Cache,
        # SSDID session store (challenges + sessions)
        {SsdidServer.SessionStore.Agent, name: SecureSharing.SsdidSessions},
        # Presence tracking for channels
        SecureSharingWeb.Presence,
        # Initialize cryptographic providers (KAZ-KEM, KAZ-SIGN, ML-KEM, ML-DSA)
        SecureSharing.Crypto.Initializer,
        # Background job processing
        {Oban, Application.fetch_env!(:secure_sharing, Oban)},
        # Start to serve requests, typically the last entry
        SecureSharingWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SecureSharing.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Register with SSDID registry asynchronously after startup
    SecureSharing.Ssdid.register_with_registry()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SecureSharingWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Returns the appropriate cluster supervisor based on configuration.
  # Uses libcluster for advanced strategies, falls back to DNSCluster for simple deployments.
  defp cluster_supervisor do
    topologies = SecureSharing.Cluster.topologies()

    if topologies == [] do
      # Fall back to DNSCluster if no libcluster topology configured
      dns_query = Application.get_env(:secure_sharing, :dns_cluster_query)

      if dns_query do
        {DNSCluster, query: dns_query}
      else
        nil
      end
    else
      {Cluster.Supervisor, [topologies, [name: SecureSharing.ClusterSupervisor]]}
    end
  end
end
