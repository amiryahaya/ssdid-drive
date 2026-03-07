defmodule SecureSharing.Cluster do
  @moduledoc """
  Cluster configuration and management for SecureSharing.

  Supports multiple clustering strategies:
  - DNS: For Kubernetes headless services and Fly.io
  - Kubernetes: Native K8s API-based discovery
  - Gossip: For development and simple deployments
  - EPMD: For static node lists

  ## Configuration

  Set the `CLUSTER_STRATEGY` environment variable to choose:
  - `dns` - DNS-based discovery (default for production)
  - `kubernetes` - Kubernetes API discovery
  - `gossip` - UDP gossip protocol
  - `epmd` - Static node list
  - `none` - Disable clustering

  ## Environment Variables

  ### DNS Strategy
  - `DNS_CLUSTER_QUERY` - DNS query for node discovery (e.g., "secure-sharing.internal")
  - `DNS_POLL_INTERVAL` - Poll interval in ms (default: 5000)

  ### Kubernetes Strategy
  - `KUBERNETES_SELECTOR` - Label selector (e.g., "app=secure-sharing")
  - `KUBERNETES_NAMESPACE` - K8s namespace (default: "default")
  - `KUBERNETES_NODE_BASENAME` - Node basename (default: "secure_sharing")

  ### Gossip Strategy
  - `GOSSIP_SECRET` - Shared secret for gossip encryption
  - `GOSSIP_PORT` - UDP port for gossip (default: 45892)

  ### EPMD Strategy
  - `CLUSTER_NODES` - Comma-separated list of nodes (e.g., "node1@host1,node2@host2")
  """

  require Logger

  @doc """
  Returns the libcluster topology configuration based on environment.
  """
  def topologies do
    strategy = System.get_env("CLUSTER_STRATEGY", "dns")

    case strategy do
      "none" ->
        Logger.info("[Cluster] Clustering disabled")
        []

      "dns" ->
        dns_topology()

      "kubernetes" ->
        kubernetes_topology()

      "gossip" ->
        gossip_topology()

      "epmd" ->
        epmd_topology()

      unknown ->
        Logger.warning("[Cluster] Unknown strategy '#{unknown}', defaulting to DNS")
        dns_topology()
    end
  end

  defp dns_topology do
    query = System.get_env("DNS_CLUSTER_QUERY")

    if query do
      poll_interval = String.to_integer(System.get_env("DNS_POLL_INTERVAL", "5000"))

      Logger.info("[Cluster] Using DNS strategy with query: #{query}")

      [
        dns: [
          strategy: Cluster.Strategy.DNSPoll,
          config: [
            polling_interval: poll_interval,
            query: query,
            node_basename: node_basename()
          ]
        ]
      ]
    else
      Logger.info("[Cluster] DNS_CLUSTER_QUERY not set, clustering disabled")
      []
    end
  end

  defp kubernetes_topology do
    selector = System.get_env("KUBERNETES_SELECTOR", "app=secure-sharing")
    namespace = System.get_env("KUBERNETES_NAMESPACE", "default")

    Logger.info("[Cluster] Using Kubernetes strategy in namespace: #{namespace}")

    [
      kubernetes: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :dns,
          kubernetes_selector: selector,
          kubernetes_node_basename: node_basename(),
          kubernetes_namespace: namespace,
          polling_interval: 5_000
        ]
      ]
    ]
  end

  defp gossip_topology do
    secret = System.get_env("GOSSIP_SECRET")

    unless secret do
      raise "GOSSIP_SECRET environment variable is required for gossip clustering"
    end

    port = String.to_integer(System.get_env("GOSSIP_PORT", "45892"))

    Logger.info("[Cluster] Using Gossip strategy on port: #{port}")

    [
      gossip: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          port: port,
          if_addr: {0, 0, 0, 0},
          multicast_if: {0, 0, 0, 0},
          multicast_addr: {230, 1, 1, 251},
          multicast_ttl: 1,
          secret: secret
        ]
      ]
    ]
  end

  defp epmd_topology do
    nodes_str = System.get_env("CLUSTER_NODES", "")

    nodes =
      nodes_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    if nodes == [] do
      Logger.info("[Cluster] No CLUSTER_NODES specified, clustering disabled")
      []
    else
      Logger.info("[Cluster] Using EPMD strategy with nodes: #{inspect(nodes)}")

      [
        epmd: [
          strategy: Cluster.Strategy.Epmd,
          config: [hosts: nodes]
        ]
      ]
    end
  end

  defp node_basename do
    System.get_env("KUBERNETES_NODE_BASENAME", "secure_sharing")
  end

  @doc """
  Returns information about the current cluster state.
  """
  def info do
    %{
      node: Node.self(),
      nodes: Node.list(),
      node_count: length(Node.list()) + 1,
      strategy: System.get_env("CLUSTER_STRATEGY", "dns"),
      connected: Node.list() != []
    }
  end

  @doc """
  Checks if the node is connected to a cluster.
  """
  def connected? do
    Node.list() != []
  end

  @doc """
  Returns the list of connected nodes including self.
  """
  def nodes do
    [Node.self() | Node.list()]
  end
end
