defmodule SecureSharing.Crypto.Initializer do
  @moduledoc """
  Initializes cryptographic providers on application startup.

  This module runs as a Task in the supervision tree to ensure
  all crypto providers are initialized before the application
  starts serving requests.

  ## Fail-Fast Behavior

  If crypto initialization fails, this process will exit with an error,
  causing the supervision tree to fail. This is intentional - the application
  should NOT start if cryptographic operations are unavailable.
  """

  use Task, restart: :temporary

  require Logger

  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    Logger.info("Initializing cryptographic providers...")

    case SecureSharing.Crypto.init() do
      :ok ->
        info = SecureSharing.Crypto.info()

        Logger.info(
          "Crypto initialized successfully. " <>
            "Available algorithms: #{inspect(info.available_algorithms)}. " <>
            "Default: KEM=#{info.default_kem.algorithm}, SIGN=#{info.default_sign.algorithm}. " <>
            "Security level: #{info.security_level}"
        )

        # Log individual algorithm status
        for algo <- info.available_algorithms do
          algo_info = SecureSharing.Crypto.info(algo)

          Logger.debug(
            "  #{algo}: KEM=#{algo_info.kem.algorithm} (init=#{algo_info.kem.initialized}), " <>
              "SIGN=#{algo_info.sign.algorithm} (init=#{algo_info.sign.initialized})"
          )
        end

        :ok

      {:error, reason} ->
        Logger.error("FATAL: Failed to initialize crypto providers: #{inspect(reason)}")
        Logger.error("Application cannot start without working cryptography.")
        # Exit with error to crash the supervision tree
        exit({:crypto_init_failed, reason})
    end
  end
end
