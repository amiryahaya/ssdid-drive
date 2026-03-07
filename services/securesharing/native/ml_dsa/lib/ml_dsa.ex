defmodule MlDsa do
  @moduledoc """
  ML-DSA (FIPS 204) Post-Quantum Digital Signature Algorithm.

  This module provides Elixir bindings to ML-DSA (Module-Lattice-based Digital Signature Algorithm)
  as standardized in FIPS 204. ML-DSA is based on the CRYSTALS-Dilithium algorithm.

  ## Security Levels

  - 128-bit (ML-DSA-44): NIST Level 2
  - 192-bit (ML-DSA-65): NIST Level 3 (recommended)
  - 256-bit (ML-DSA-87): NIST Level 5

  ## Usage

      # Initialize with security level (128, 192, or 256)
      :ok = MlDsa.init(192)

      # Generate keypair
      {:ok, public_key, secret_key} = MlDsa.keypair()

      # Sign a message
      message = "Hello, Post-Quantum World!"
      {:ok, signature} = MlDsa.sign(message, secret_key)

      # Verify the signature
      true = MlDsa.verify(message, signature, public_key)
  """

  alias MlDsa.Nif

  @type security_level :: 128 | 192 | 256
  @type public_key :: binary()
  @type secret_key :: binary()
  @type signature :: binary()

  @doc """
  Initialize ML-DSA with the specified security level.

  ## Parameters

  - `level` - Security level: 128 (ML-DSA-44), 192 (ML-DSA-65), or 256 (ML-DSA-87)

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec init(security_level()) :: :ok | {:error, atom()}
  def init(level) when level in [128, 192, 256] do
    Nif.nif_init(level)
  end

  def init(_level), do: {:error, :invalid_level}

  @doc """
  Check if ML-DSA has been initialized.

  ## Returns

  - `true` if initialized
  - `false` if not initialized
  """
  @spec initialized?() :: boolean()
  def initialized? do
    Nif.nif_is_initialized() == :true
  end

  @doc """
  Get the current security level.

  ## Returns

  - `{:ok, level}` where level is 128, 192, or 256
  - `{:error, :not_initialized}` if not initialized
  """
  @spec get_level() :: {:ok, security_level()} | {:error, :not_initialized}
  def get_level do
    Nif.nif_get_level()
  end

  @doc """
  Get the key and signature sizes for the current security level.

  ## Returns

  - `{:ok, {public_key_size, secret_key_size, signature_size}}`
  - `{:error, :not_initialized}` if not initialized
  """
  @spec get_sizes() :: {:ok, {pos_integer(), pos_integer(), pos_integer()}} | {:error, :not_initialized}
  def get_sizes do
    Nif.nif_get_sizes()
  end

  @doc """
  Generate a new ML-DSA keypair.

  Must call `init/1` before generating keypairs.

  ## Returns

  - `{:ok, public_key, secret_key}` on success
  - `{:error, reason}` on failure
  """
  @spec keypair() :: {:ok, public_key(), secret_key()} | {:error, atom()}
  def keypair do
    Nif.nif_keypair()
  end

  @doc """
  Sign a message using a secret key.

  ## Parameters

  - `message` - The message to sign (binary)
  - `secret_key` - The signer's secret key

  ## Returns

  - `{:ok, signature}` on success
  - `{:error, reason}` on failure
  """
  @spec sign(binary(), secret_key()) :: {:ok, signature()} | {:error, atom()}
  def sign(message, secret_key) when is_binary(message) and is_binary(secret_key) do
    Nif.nif_sign(message, secret_key)
  end

  @doc """
  Verify a signature.

  ## Parameters

  - `message` - The original message (binary)
  - `signature` - The signature to verify
  - `public_key` - The signer's public key

  ## Returns

  - `true` if the signature is valid
  - `false` if the signature is invalid
  """
  @spec verify(binary(), signature(), public_key()) :: boolean()
  def verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    Nif.nif_verify(message, signature, public_key) == :true
  end

  @doc """
  Clean up ML-DSA resources.

  Releases the SIG instance and clears the security level.
  """
  @spec cleanup() :: :ok
  def cleanup do
    Nif.nif_cleanup()
  end

  @doc """
  Get version information.

  ## Returns

  - `{:ok, {ml_dsa_version, liboqs_version}}`
  """
  @spec version() :: {:ok, {String.t(), String.t()}}
  def version do
    Nif.nif_version()
  end
end
