defmodule SecureSharing.Ssdid do
  @moduledoc """
  SSDID identity management for SecureSharing.

  Initializes the server's SSDID identity on startup and provides
  access to the SSDID context for authentication operations.

  ## Architecture

  SecureSharing uses pure SSDID authentication:
  - No email/password — identity is DID + keypair
  - No JWT tokens — SSDID session tokens via challenge-response
  - Mutual authentication — server proves identity to client
  - Transaction signing — per-operation challenge-response with hash binding
  """

  require Logger

  @doc """
  Initialize the SSDID server identity and context.

  Called during application startup. Creates or loads the server's keypair,
  registers with the SSDID registry, and configures the session store.
  """
  def init do
    password = identity_password()
    algorithm = Application.get_env(:secure_sharing, :ssdid_algorithm, :ed25519)

    Logger.info("Initializing SSDID identity (algorithm: #{algorithm})...")

    case SsdidServer.Bootstrap.init_identity("securesharing-key", password, algorithm: algorithm) do
      {:ok, identity} ->
        ctx = %SsdidServer.Context{
          identity: identity,
          session_store_mod: SsdidServer.SessionStore.Agent,
          session_store_name: SecureSharing.SsdidSessions,
          service_name: "securesharing"
        }

        SsdidServer.set_context(ctx)
        Logger.info("SSDID identity initialized: #{identity.did}")
        {:ok, identity}

      {:error, reason} ->
        Logger.error("Failed to initialize SSDID identity: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Asynchronously register with the SSDID registry.

  Called after the supervisor starts. Retries with exponential backoff.
  """
  def register_with_registry do
    registry_url = Application.get_env(:secure_sharing, :ssdid_registry_url, "https://registry.ssdid.my")

    Task.start(fn ->
      ctx = SsdidServer.get_context()

      registry_opts = [
        registry_adapter: :http,
        registry_url: registry_url
      ]

      case SsdidServer.Bootstrap.register_with_registry(ctx.identity, registry_opts) do
        {:ok, _} ->
          Logger.info("Registered with SSDID registry at #{registry_url}")

        {:error, reason} ->
          Logger.warning("Failed to register with SSDID registry: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Get the current SSDID context.
  """
  def context do
    SsdidServer.get_context()
  end

  @doc """
  Get the server's DID.
  """
  def server_did do
    SsdidServer.get_context().identity.did
  end

  defp identity_password do
    System.get_env("SSDID_IDENTITY_PASSWORD") ||
      Application.get_env(:secure_sharing, :ssdid_identity_password) ||
      raise "SSDID_IDENTITY_PASSWORD environment variable is required"
  end
end
