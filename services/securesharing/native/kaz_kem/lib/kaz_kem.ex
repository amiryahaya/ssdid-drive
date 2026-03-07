defmodule KazKem do
  @moduledoc """
  KAZ-KEM - Post-Quantum Key Encapsulation Mechanism.

  KAZ-KEM is a post-quantum secure key encapsulation mechanism based on
  the discrete logarithm problem in finite groups with unknown order.

  ## Security Levels

  - `128` - 128-bit security (recommended for most applications)
  - `192` - 192-bit security (high security)
  - `256` - 256-bit security (paranoid security)

  ## Usage

      # Initialize with security level
      :ok = KazKem.init(128)

      # Generate keypair
      {:ok, keypair} = KazKem.keypair()

      # Encapsulate a shared secret
      shared_secret = :crypto.strong_rand_bytes(32)
      {:ok, ciphertext} = KazKem.encapsulate(shared_secret, keypair.public_key)

      # Decapsulate to recover the shared secret
      {:ok, recovered_secret} = KazKem.decapsulate(ciphertext, keypair.private_key)

      # Cleanup when done
      :ok = KazKem.cleanup()

  ## Thread Safety

  The NIF bindings use a mutex to ensure thread-safe access to the
  underlying C library. However, only one security level can be active
  at a time globally.
  """

  alias KazKem.Nif

  @type level :: 128 | 192 | 256
  @type keypair :: %{public_key: binary(), private_key: binary()}
  @type sizes :: %{
          public_key: non_neg_integer(),
          private_key: non_neg_integer(),
          ciphertext: non_neg_integer(),
          shared_secret: non_neg_integer()
        }

  @doc """
  Initialize KAZ-KEM with the specified security level.

  Must be called before any other KAZ-KEM operations.

  ## Parameters

  - `level` - Security level: 128, 192, or 256

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> KazKem.init(128)
      :ok

      iex> KazKem.init(999)
      {:error, :invalid_level}
  """
  @spec init(level()) :: :ok | {:error, atom()}
  def init(level) when level in [128, 192, 256] do
    Nif.nif_init(level)
  end

  def init(_level), do: {:error, :invalid_level}

  @doc """
  Check if KAZ-KEM has been initialized.

  ## Returns

  - `true` if initialized
  - `false` if not initialized
  """
  @spec initialized?() :: boolean()
  def initialized? do
    Nif.nif_is_initialized() == true
  end

  @doc """
  Get the current security level.

  ## Returns

  - `{:ok, level}` where level is 128, 192, or 256
  - `{:error, :not_initialized}` if not initialized
  """
  @spec get_level() :: {:ok, level()} | {:error, :not_initialized}
  def get_level do
    Nif.nif_get_level()
  end

  @doc """
  Get the sizes of keys and ciphertext for the current security level.

  ## Returns

  - `{:ok, sizes}` with a map containing:
    - `:public_key` - public key size in bytes
    - `:private_key` - private key size in bytes
    - `:ciphertext` - ciphertext size in bytes
    - `:shared_secret` - shared secret size in bytes
  - `{:error, :not_initialized}` if not initialized
  """
  @spec get_sizes() :: {:ok, sizes()} | {:error, :not_initialized}
  def get_sizes do
    Nif.nif_get_sizes()
  end

  @doc """
  Generate a new KEM keypair.

  ## Returns

  - `{:ok, keypair}` with a map containing:
    - `:public_key` - the public key binary
    - `:private_key` - the private key binary
  - `{:error, reason}` on failure

  ## Examples

      iex> KazKem.init(128)
      :ok
      iex> {:ok, keypair} = KazKem.keypair()
      iex> is_binary(keypair.public_key)
      true
  """
  @spec keypair() :: {:ok, keypair()} | {:error, atom()}
  def keypair do
    Nif.nif_keypair()
  end

  @doc """
  Encapsulate a shared secret using a public key.

  The shared secret will be encrypted and can only be recovered
  by the holder of the corresponding private key.

  Note: The C library expects the shared secret to be exactly `shared_secret`
  bytes (54 for level 128, 88 for level 192, 118 for level 256). This function
  automatically pads shorter inputs with leading zeros. The secret is treated
  as a big-endian number, so leading zeros don't change the value.

  ## Parameters

  - `shared_secret` - The secret to encapsulate (binary, up to `shared_secret` bytes)
  - `public_key` - The recipient's public key

  ## Returns

  - `{:ok, ciphertext}` - The encapsulated ciphertext
  - `{:error, reason}` on failure

  ## Examples

      iex> :ok = KazKem.init(128)
      iex> {:ok, keypair} = KazKem.keypair()
      iex> secret = :crypto.strong_rand_bytes(16)
      iex> {:ok, ciphertext} = KazKem.encapsulate(secret, keypair.public_key)
      iex> is_binary(ciphertext)
      true
  """
  @spec encapsulate(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def encapsulate(shared_secret, public_key)
      when is_binary(shared_secret) and is_binary(public_key) do
    with {:ok, sizes} <- get_sizes() do
      ss_size = sizes.shared_secret
      secret_len = byte_size(shared_secret)

      padded_secret =
        cond do
          secret_len == ss_size ->
            shared_secret

          secret_len < ss_size ->
            # Left-pad with zeros (big-endian format)
            padding = :binary.copy(<<0>>, ss_size - secret_len)
            padding <> shared_secret

          true ->
            # Too large - let C library handle the error
            shared_secret
        end

      Nif.nif_encapsulate(padded_secret, public_key)
    end
  end

  @doc """
  Decapsulate a ciphertext to recover the shared secret.

  Note: The original secret length is passed to trim the result.
  If not provided, returns the full buffer which may include leading zeros.

  ## Parameters

  - `ciphertext` - The encapsulated ciphertext
  - `private_key` - The private key
  - `original_length` - (optional) Original secret length to trim result

  ## Returns

  - `{:ok, shared_secret}` - The recovered shared secret
  - `{:error, reason}` on failure

  ## Examples

      iex> :ok = KazKem.init(128)
      iex> {:ok, keypair} = KazKem.keypair()
      iex> secret = :crypto.strong_rand_bytes(16)
      iex> {:ok, ciphertext} = KazKem.encapsulate(secret, keypair.public_key)
      iex> {:ok, recovered} = KazKem.decapsulate(ciphertext, keypair.private_key, 16)
      iex> recovered == secret
      true
  """
  @spec decapsulate(binary(), binary(), non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, atom()}
  def decapsulate(ciphertext, private_key, original_length \\ nil)

  def decapsulate(ciphertext, private_key, nil)
      when is_binary(ciphertext) and is_binary(private_key) do
    Nif.nif_decapsulate(ciphertext, private_key)
  end

  def decapsulate(ciphertext, private_key, original_length)
      when is_binary(ciphertext) and is_binary(private_key) and is_integer(original_length) and
             original_length > 0 do
    case Nif.nif_decapsulate(ciphertext, private_key) do
      {:ok, recovered} ->
        # Trim leading zeros and return last `original_length` bytes
        recovered_len = byte_size(recovered)

        if recovered_len >= original_length do
          {:ok, binary_part(recovered, recovered_len - original_length, original_length)}
        else
          {:ok, recovered}
        end

      error ->
        error
    end
  end

  @doc """
  Cleanup KAZ-KEM state and free resources.

  Should be called when KAZ-KEM is no longer needed.

  ## Returns

  - `:ok`
  """
  @spec cleanup() :: :ok
  def cleanup do
    Nif.nif_cleanup()
  end

  @doc """
  Get the KAZ-KEM library version.

  ## Returns

  Version string (e.g., "2.1.0")
  """
  @spec version() :: String.t()
  def version do
    Nif.nif_version() |> to_string()
  end
end
