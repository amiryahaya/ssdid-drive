defmodule MlKem do
  @moduledoc """
  ML-KEM (FIPS 203) Post-Quantum Key Encapsulation Mechanism.

  This module provides Elixir bindings to ML-KEM (Module-Lattice-based Key Encapsulation Mechanism)
  as standardized in FIPS 203. ML-KEM is based on the CRYSTALS-Kyber algorithm.

  ## Security Levels

  - 128-bit (ML-KEM-512): NIST Level 1
  - 192-bit (ML-KEM-768): NIST Level 3 (recommended)
  - 256-bit (ML-KEM-1024): NIST Level 5

  ## Usage

      # Initialize with security level (128, 192, or 256)
      :ok = MlKem.init(192)

      # Generate keypair
      {:ok, public_key, secret_key} = MlKem.keypair()

      # Encapsulate - generates ciphertext and shared secret
      {:ok, ciphertext, shared_secret} = MlKem.encapsulate(public_key)

      # Decapsulate - recovers shared secret from ciphertext
      {:ok, ^shared_secret} = MlKem.decapsulate(ciphertext, secret_key)
  """

  alias MlKem.Nif

  @type security_level :: 128 | 192 | 256
  @type public_key :: binary()
  @type secret_key :: binary()
  @type ciphertext :: binary()
  @type shared_secret :: binary()

  @doc """
  Initialize ML-KEM with the specified security level.

  ## Parameters

  - `level` - Security level: 128 (ML-KEM-512), 192 (ML-KEM-768), or 256 (ML-KEM-1024)

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
  Check if ML-KEM has been initialized.

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
  Get the key and ciphertext sizes for the current security level.

  ## Returns

  - `{:ok, {public_key_size, secret_key_size, ciphertext_size, shared_secret_size}}`
  - `{:error, :not_initialized}` if not initialized
  """
  @spec get_sizes() :: {:ok, {pos_integer(), pos_integer(), pos_integer(), pos_integer()}} | {:error, :not_initialized}
  def get_sizes do
    Nif.nif_get_sizes()
  end

  @doc """
  Generate a new ML-KEM keypair.

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
  Encapsulate a shared secret using a public key.

  Generates a random shared secret and encrypts it with the recipient's public key.
  The ciphertext can only be decapsulated by the holder of the corresponding secret key.

  ## Parameters

  - `public_key` - The recipient's public key

  ## Returns

  - `{:ok, ciphertext, shared_secret}` on success
  - `{:error, reason}` on failure
  """
  @spec encapsulate(public_key()) :: {:ok, ciphertext(), shared_secret()} | {:error, atom()}
  def encapsulate(public_key) when is_binary(public_key) do
    Nif.nif_encapsulate(public_key)
  end

  @doc """
  Decapsulate a ciphertext using a secret key.

  Recovers the shared secret that was encapsulated using the corresponding public key.

  ## Parameters

  - `ciphertext` - The ciphertext from encapsulation
  - `secret_key` - The recipient's secret key

  ## Returns

  - `{:ok, shared_secret}` on success
  - `{:error, reason}` on failure
  """
  @spec decapsulate(ciphertext(), secret_key()) :: {:ok, shared_secret()} | {:error, atom()}
  def decapsulate(ciphertext, secret_key) when is_binary(ciphertext) and is_binary(secret_key) do
    Nif.nif_decapsulate(ciphertext, secret_key)
  end

  @doc """
  Clean up ML-KEM resources.

  Releases the KEM instance and clears the security level.
  """
  @spec cleanup() :: :ok
  def cleanup do
    Nif.nif_cleanup()
  end

  @doc """
  Get version information.

  ## Returns

  - `{:ok, {ml_kem_version, liboqs_version}}`
  """
  @spec version() :: {:ok, {String.t(), String.t()}}
  def version do
    Nif.nif_version()
  end
end
