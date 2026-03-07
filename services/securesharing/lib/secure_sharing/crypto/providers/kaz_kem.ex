defmodule SecureSharing.Crypto.Providers.KazKEM do
  @moduledoc """
  KAZ-KEM provider implementation.

  Wraps the KazKem NIF module to conform to the KEMProvider behaviour.

  KAZ-KEM is a post-quantum secure key encapsulation mechanism based on
  the discrete logarithm problem in finite groups with unknown order.

  ## KEM Semantics

  This provider adapts KAZ-KEM's native key-wrapping interface to standard
  KEM semantics:
  - `encapsulate(pk)` generates a random 32-byte shared secret, wraps it
  - `decapsulate(ct, sk)` recovers the shared secret
  """

  @behaviour SecureSharing.Crypto.KEMProvider

  # Shared secret size in bytes (256-bit)
  @shared_secret_size 32

  @impl true
  def init(level) when level in [128, 192, 256] do
    KazKem.init(level)
  end

  def init(_level), do: {:error, :invalid_level}

  @impl true
  def initialized?, do: KazKem.initialized?()

  @impl true
  def get_level, do: KazKem.get_level()

  @impl true
  def get_sizes, do: KazKem.get_sizes()

  @impl true
  def keypair, do: KazKem.keypair()

  @impl true
  def encapsulate(public_key) do
    # Generate a random shared secret
    shared_secret = :crypto.strong_rand_bytes(@shared_secret_size)

    # Use KAZ-KEM's native key-wrapping to encapsulate it
    {:ok, ciphertext} = KazKem.encapsulate(shared_secret, public_key)
    {:ok, %{ciphertext: ciphertext, shared_secret: shared_secret}}
  end

  @impl true
  def decapsulate(ciphertext, private_key) do
    # KAZ-KEM native decapsulation recovers the shared secret
    KazKem.decapsulate(ciphertext, private_key, @shared_secret_size)
  end

  @impl true
  def cleanup, do: KazKem.cleanup()

  @impl true
  def version, do: KazKem.version()

  @impl true
  def algorithm, do: "KAZ-KEM"
end
