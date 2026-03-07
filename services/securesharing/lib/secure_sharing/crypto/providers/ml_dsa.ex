defmodule SecureSharing.Crypto.Providers.MLDSA do
  @moduledoc """
  ML-DSA (NIST FIPS 204) provider implementation.

  Wraps the MlDsa NIF module to conform to the SignProvider behaviour.

  ML-DSA-65 provides approximately 192-bit classical security and
  128-bit post-quantum security (NIST security level 3).

  ## Note on API Difference

  Unlike KAZ-SIGN which is a message-recovery signature scheme,
  ML-DSA is a standard appendix signature scheme. The `verify/3` function
  returns the original message if verification succeeds, maintaining
  API compatibility with KAZ-SIGN.
  """

  @behaviour SecureSharing.Crypto.SignProvider

  @impl true
  def init do
    # ML-DSA-65 provides ~192-bit classical security (NIST level 3)
    MlDsa.init(192)
  end

  @impl true
  def init(_level) do
    # We use ML-DSA-65 which is fixed at ~192-bit classical security
    # The level parameter is accepted for API compatibility but ignored
    MlDsa.init(192)
  end

  @impl true
  def initialized?, do: MlDsa.initialized?()

  @impl true
  def get_sizes(_level) do
    MlDsa.get_sizes()
  end

  @impl true
  def keypair(_level \\ 128) do
    case MlDsa.keypair() do
      {:ok, public_key, private_key} ->
        {:ok, %{public_key: public_key, private_key: private_key}}

      other ->
        other
    end
  end

  @impl true
  def sign(_level, message, private_key) do
    case MlDsa.sign(message, private_key) do
      {:ok, signature} ->
        # Store message length and message with signature for recovery
        msg_len = byte_size(message)
        {:ok, <<msg_len::32, message::binary, signature::binary>>}

      error ->
        error
    end
  end

  @impl true
  def verify(_level, combined_signature, public_key) do
    # Extract message and signature
    case combined_signature do
      <<msg_len::32, rest::binary>> when byte_size(rest) >= msg_len ->
        <<message::binary-size(msg_len), signature::binary>> = rest

        if MlDsa.verify(message, signature, public_key) do
          {:ok, message}
        else
          {:error, :invalid_signature}
        end

      _ ->
        {:error, :invalid_signature_format}
    end
  end

  @impl true
  def valid?(_level, combined_signature, public_key) do
    case verify(128, combined_signature, public_key) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def hash(_level, message) do
    # Use SHA-384 to match the security level
    {:ok, :crypto.hash(:sha384, message)}
  end

  @impl true
  def cleanup, do: MlDsa.cleanup()

  @impl true
  def version, do: MlDsa.version()

  @impl true
  def algorithm, do: "ML-DSA-65"

  # Additional ML-DSA specific functions

  @doc """
  ML-DSA native sign that returns just the signature.
  """
  @spec native_sign(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def native_sign(message, private_key) do
    MlDsa.sign(message, private_key)
  end

  @doc """
  ML-DSA native verify that returns boolean.
  """
  @spec native_verify(binary(), binary(), binary()) :: boolean()
  def native_verify(message, signature, public_key) do
    MlDsa.verify(message, signature, public_key)
  end
end
