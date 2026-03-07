defmodule SecureSharing.Crypto.SignProvider do
  @moduledoc """
  Behaviour for Digital Signature providers.

  Digital signatures are used to ensure authenticity and integrity of data.
  This behaviour allows swapping between different signature implementations
  (e.g., KAZ-SIGN, ML-DSA) for algorithm agility.

  ## Security Levels

  All implementations must support these security levels:
  - 128 - 128-bit security
  - 192 - 192-bit security
  - 256 - 256-bit security

  ## Usage

      # Get the configured provider
      provider = SecureSharing.Crypto.sign_provider()

      # Initialize
      :ok = provider.init()

      # Generate keypair for a specific level
      {:ok, keypair} = provider.keypair(128)

      # Sign a message
      {:ok, signature} = provider.sign(128, message, private_key)

      # Verify signature
      {:ok, recovered_message} = provider.verify(128, signature, public_key)
  """

  @type level :: 128 | 192 | 256
  @type keypair :: %{public_key: binary(), private_key: binary()}
  @type sizes :: %{
          public_key: non_neg_integer(),
          private_key: non_neg_integer(),
          hash: non_neg_integer(),
          signature_overhead: non_neg_integer()
        }

  @doc """
  Initialize the signature provider.
  """
  @callback init() :: :ok | {:error, atom()}

  @doc """
  Initialize the signature provider for a specific security level.
  """
  @callback init(level()) :: :ok | {:error, atom()}

  @doc """
  Check if the provider has been initialized.
  """
  @callback initialized?() :: boolean()

  @doc """
  Get the sizes of keys and signatures for a specific security level.
  """
  @callback get_sizes(level()) :: {:ok, sizes()} | {:error, atom()}

  @doc """
  Generate a new signing keypair for a specific security level.
  """
  @callback keypair(level()) :: {:ok, keypair()} | {:error, atom()}

  @doc """
  Sign a message.
  """
  @callback sign(level(), message :: binary(), private_key :: binary()) ::
              {:ok, signature :: binary()} | {:error, atom()}

  @doc """
  Verify a signature and recover the original message.
  """
  @callback verify(level(), signature :: binary(), public_key :: binary()) ::
              {:ok, message :: binary()} | {:error, atom()}

  @doc """
  Check if a signature is valid without recovering the message.
  """
  @callback valid?(level(), signature :: binary(), public_key :: binary()) :: boolean()

  @doc """
  Hash a message using the level-specific hash function.
  """
  @callback hash(level(), message :: binary()) :: {:ok, binary()} | {:error, atom()}

  @doc """
  Cleanup resources.
  """
  @callback cleanup() :: :ok

  @doc """
  Get the provider version.
  """
  @callback version() :: String.t()

  @doc """
  Get the algorithm name (e.g., "KAZ-SIGN", "ML-DSA").
  """
  @callback algorithm() :: String.t()

  @optional_callbacks [init: 1, valid?: 3, hash: 2]
end
