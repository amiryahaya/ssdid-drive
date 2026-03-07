defmodule SecureSharing.Crypto.Providers.KazSign do
  @moduledoc """
  KAZ-SIGN provider implementation.

  Wraps the KazSign NIF module to conform to the SignProvider behaviour.

  KAZ-SIGN is a post-quantum secure digital signature scheme based on
  the discrete logarithm problem in finite groups with unknown order.
  """

  @behaviour SecureSharing.Crypto.SignProvider

  @impl true
  def init, do: KazSign.init()

  @impl true
  def init(level) when level in [128, 192, 256] do
    KazSign.init(level)
  end

  def init(_level), do: {:error, :invalid_level}

  @impl true
  def initialized?, do: KazSign.initialized?()

  @impl true
  def get_sizes(level), do: KazSign.get_sizes(level)

  @impl true
  def keypair(level), do: KazSign.keypair(level)

  @impl true
  def sign(level, message, private_key) do
    KazSign.sign(level, message, private_key)
  end

  @impl true
  def verify(level, signature, public_key) do
    KazSign.verify(level, signature, public_key)
  end

  @impl true
  def valid?(level, signature, public_key) do
    KazSign.valid?(level, signature, public_key)
  end

  @impl true
  def hash(level, message), do: KazSign.hash(level, message)

  @impl true
  def cleanup, do: KazSign.cleanup()

  @impl true
  def version, do: KazSign.version()

  @impl true
  def algorithm, do: "KAZ-SIGN"
end
