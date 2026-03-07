defmodule KazSign do
  @moduledoc """
  KAZ-SIGN - Post-Quantum Digital Signature Scheme.

  KAZ-SIGN is a post-quantum secure digital signature scheme based on
  the discrete logarithm problem in finite groups with unknown order.

  ## Security Levels

  - `128` - 128-bit security (SHA-256 based)
  - `192` - 192-bit security (SHA-384 based)
  - `256` - 256-bit security (SHA-512 based)

  ## Signature Format

  KAZ-SIGN uses a message-recovery signature scheme. The signature
  includes the original message, and verification recovers the message.

  ## Usage

      # Initialize (required once)
      :ok = KazSign.init()

      # Generate keypair for level 128
      {:ok, keypair} = KazSign.keypair(128)

      # Sign a message
      {:ok, signature} = KazSign.sign(128, "Hello, World!", keypair.private_key)

      # Verify and recover message
      {:ok, message} = KazSign.verify(128, signature, keypair.public_key)

      # Cleanup when done
      :ok = KazSign.cleanup()

  ## Thread Safety

  The NIF bindings use a mutex to ensure thread-safe access to the
  underlying C library.
  """

  alias KazSign.Nif

  @type level :: 128 | 192 | 256
  @type keypair :: %{public_key: binary(), private_key: binary()}
  @type sizes :: %{
          public_key: non_neg_integer(),
          private_key: non_neg_integer(),
          hash: non_neg_integer(),
          signature_overhead: non_neg_integer()
        }

  @doc """
  Initialize KAZ-SIGN random number generator.

  Must be called before any other KAZ-SIGN operations.

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec init() :: :ok | {:error, atom()}
  def init do
    Nif.nif_init()
  end

  @doc """
  Initialize KAZ-SIGN for a specific security level.

  Also initializes the RNG if not already initialized.

  ## Parameters

  - `level` - Security level: 128, 192, or 256

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec init(level()) :: :ok | {:error, atom()}
  def init(level) when level in [128, 192, 256] do
    Nif.nif_init_level(level)
  end

  def init(_level), do: {:error, :invalid_level}

  @doc """
  Check if KAZ-SIGN has been initialized.

  ## Returns

  - `true` if initialized
  - `false` if not initialized
  """
  @spec initialized?() :: boolean()
  def initialized? do
    Nif.nif_is_initialized() == true
  end

  @doc """
  Get the sizes of keys and signatures for a specific security level.

  ## Parameters

  - `level` - Security level: 128, 192, or 256

  ## Returns

  - `{:ok, sizes}` with a map containing:
    - `:public_key` - public key size in bytes
    - `:private_key` - private key size in bytes
    - `:hash` - hash output size in bytes
    - `:signature_overhead` - signature overhead in bytes (actual signature = overhead + message length)
  - `{:error, reason}` on failure
  """
  @spec get_sizes(level()) :: {:ok, sizes()} | {:error, atom()}
  def get_sizes(level) when level in [128, 192, 256] do
    Nif.nif_get_sizes(level)
  end

  def get_sizes(_level), do: {:error, :invalid_level}

  @doc """
  Generate a new signing keypair.

  ## Parameters

  - `level` - Security level: 128, 192, or 256

  ## Returns

  - `{:ok, keypair}` with a map containing:
    - `:public_key` - the public key binary
    - `:private_key` - the private key binary
  - `{:error, reason}` on failure

  ## Examples

      iex> KazSign.init()
      :ok
      iex> {:ok, keypair} = KazSign.keypair(128)
      iex> is_binary(keypair.public_key)
      true
  """
  @spec keypair(level()) :: {:ok, keypair()} | {:error, atom()}
  def keypair(level) when level in [128, 192, 256] do
    Nif.nif_keypair(level)
  end

  def keypair(_level), do: {:error, :invalid_level}

  @doc """
  Sign a message.

  The signature includes the message (message-recovery scheme).

  ## Parameters

  - `level` - Security level: 128, 192, or 256
  - `message` - The message to sign (binary or string)
  - `private_key` - The private key

  ## Returns

  - `{:ok, signature}` - The signature containing the message
  - `{:error, reason}` on failure

  ## Examples

      iex> {:ok, keypair} = KazSign.keypair(128)
      iex> {:ok, signature} = KazSign.sign(128, "Hello!", keypair.private_key)
      iex> is_binary(signature)
      true
  """
  @spec sign(level(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def sign(level, message, private_key)
      when level in [128, 192, 256] and is_binary(message) and is_binary(private_key) do
    Nif.nif_sign(level, message, private_key)
  end

  def sign(_level, _message, _private_key), do: {:error, :invalid_argument}

  @doc """
  Verify a signature and recover the original message.

  ## Parameters

  - `level` - Security level: 128, 192, or 256
  - `signature` - The signature to verify
  - `public_key` - The public key

  ## Returns

  - `{:ok, message}` - The recovered original message
  - `{:error, :invalid_signature}` - If verification fails
  - `{:error, reason}` - On other errors

  ## Examples

      iex> {:ok, keypair} = KazSign.keypair(128)
      iex> {:ok, signature} = KazSign.sign(128, "Hello!", keypair.private_key)
      iex> {:ok, message} = KazSign.verify(128, signature, keypair.public_key)
      iex> message
      "Hello!"
  """
  @spec verify(level(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def verify(level, signature, public_key)
      when level in [128, 192, 256] and is_binary(signature) and is_binary(public_key) do
    Nif.nif_verify(level, signature, public_key)
  end

  def verify(_level, _signature, _public_key), do: {:error, :invalid_argument}

  @doc """
  Verify a signature without recovering the message.

  Returns `true` if the signature is valid, `false` otherwise.

  ## Parameters

  - `level` - Security level: 128, 192, or 256
  - `signature` - The signature to verify
  - `public_key` - The public key

  ## Returns

  - `true` if signature is valid
  - `false` if signature is invalid
  """
  @spec valid?(level(), binary(), binary()) :: boolean()
  def valid?(level, signature, public_key) do
    case verify(level, signature, public_key) do
      {:ok, _message} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Hash a message using the level-specific hash function.

  - Level 128: SHA-256 (32 bytes)
  - Level 192: SHA-384 (48 bytes)
  - Level 256: SHA-512 (64 bytes)

  ## Parameters

  - `level` - Security level: 128, 192, or 256
  - `message` - The message to hash

  ## Returns

  - `{:ok, hash}` - The hash digest
  - `{:error, reason}` on failure
  """
  @spec hash(level(), binary()) :: {:ok, binary()} | {:error, atom()}
  def hash(level, message) when level in [128, 192, 256] and is_binary(message) do
    Nif.nif_hash(level, message)
  end

  def hash(_level, _message), do: {:error, :invalid_argument}

  @doc """
  Cleanup KAZ-SIGN state and free resources.

  Should be called when KAZ-SIGN is no longer needed.

  ## Returns

  - `:ok`
  """
  @spec cleanup() :: :ok
  def cleanup do
    Nif.nif_cleanup()
  end

  @doc """
  Get the KAZ-SIGN library version.

  ## Returns

  Version string (e.g., "2.1.0")
  """
  @spec version() :: String.t()
  def version do
    Nif.nif_version() |> to_string()
  end
end
