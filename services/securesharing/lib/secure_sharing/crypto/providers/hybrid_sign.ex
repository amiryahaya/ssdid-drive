defmodule SecureSharing.Crypto.Providers.HybridSign do
  @moduledoc """
  Hybrid signature provider combining KAZ-SIGN and ML-DSA for defense in depth.

  This provider signs messages using both algorithms. Verification requires
  both signatures to be valid, providing security even if one algorithm
  is compromised.

  ## Security Model

  A message is considered authentically signed only if BOTH:
  - The KAZ-SIGN signature is valid
  - The ML-DSA signature is valid

  This provides defense against algorithmic breaks in either scheme.
  """

  @behaviour SecureSharing.Crypto.SignProvider

  alias SecureSharing.Crypto.Providers.{KazSign, MLDSA}

  @impl true
  def init do
    with :ok <- KazSign.init(),
         :ok <- MLDSA.init() do
      :ok
    end
  end

  @impl true
  def init(level) do
    with :ok <- KazSign.init(level),
         :ok <- MLDSA.init(level) do
      :ok
    end
  end

  @impl true
  def initialized? do
    KazSign.initialized?() and MLDSA.initialized?()
  end

  @impl true
  def get_sizes(level) do
    with {:ok, kaz_sizes} <- KazSign.get_sizes(level),
         {:ok, ml_sizes} <- MLDSA.get_sizes(level) do
      {:ok,
       %{
         public_key: kaz_sizes.public_key + ml_sizes.public_key + 8,
         private_key: kaz_sizes.private_key + ml_sizes.private_key + 8,
         hash: kaz_sizes.hash,
         signature_overhead: kaz_sizes.signature_overhead + ml_sizes.signature + 16
       }}
    end
  end

  @impl true
  def keypair(level \\ 128) do
    with {:ok, kaz_keypair} <- KazSign.keypair(level),
         {:ok, ml_keypair} <- MLDSA.keypair(level) do
      kaz_pub_len = byte_size(kaz_keypair.public_key)
      kaz_priv_len = byte_size(kaz_keypair.private_key)

      public_key = <<
        kaz_pub_len::32,
        kaz_keypair.public_key::binary,
        byte_size(ml_keypair.public_key)::32,
        ml_keypair.public_key::binary
      >>

      private_key = <<
        kaz_priv_len::32,
        kaz_keypair.private_key::binary,
        byte_size(ml_keypair.private_key)::32,
        ml_keypair.private_key::binary
      >>

      {:ok, %{public_key: public_key, private_key: private_key}}
    end
  end

  @impl true
  def sign(level, message, combined_private_key) do
    with {:ok, {kaz_sk, ml_sk}} <- parse_private_key(combined_private_key),
         {:ok, kaz_sig} <- KazSign.sign(level, message, kaz_sk),
         {:ok, ml_sig} <- MLDSA.native_sign(message, ml_sk) do
      # Build combined signature
      combined = <<
        byte_size(message)::32,
        message::binary,
        byte_size(kaz_sig)::32,
        kaz_sig::binary,
        byte_size(ml_sig)::32,
        ml_sig::binary
      >>

      {:ok, combined}
    end
  end

  @impl true
  def verify(level, combined_signature, combined_public_key) do
    with {:ok, {kaz_pk, ml_pk}} <- parse_public_key(combined_public_key),
         {:ok, {message, kaz_sig, ml_sig}} <- parse_signature(combined_signature),
         # Verify KAZ-SIGN
         {:ok, kaz_msg} <- KazSign.verify(level, kaz_sig, kaz_pk),
         # Verify ML-DSA
         true <- MLDSA.native_verify(message, ml_sig, ml_pk) do
      # Both signatures valid and KAZ-SIGN recovered the same message
      if kaz_msg == message do
        {:ok, message}
      else
        {:error, :message_mismatch}
      end
    else
      false -> {:error, :invalid_signature}
      error -> error
    end
  end

  @impl true
  def valid?(level, combined_signature, combined_public_key) do
    case verify(level, combined_signature, combined_public_key) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def hash(level, message) do
    KazSign.hash(level, message)
  end

  @impl true
  def cleanup do
    KazSign.cleanup()
    MLDSA.cleanup()
    :ok
  end

  @impl true
  def version do
    {:ok, {ml_version, _}} = MLDSA.version()
    "#{KazSign.version()}+#{ml_version}"
  end

  @impl true
  def algorithm do
    "Hybrid(KAZ-SIGN+ML-DSA-65)"
  end

  # Private helpers

  defp parse_public_key(<<kaz_len::32, rest::binary>>) when byte_size(rest) >= kaz_len + 4 do
    <<kaz_pk::binary-size(kaz_len), ml_len::32, rest2::binary>> = rest

    if byte_size(rest2) >= ml_len do
      <<ml_pk::binary-size(ml_len), _::binary>> = rest2
      {:ok, {kaz_pk, ml_pk}}
    else
      {:error, :invalid_public_key}
    end
  end

  defp parse_public_key(_), do: {:error, :invalid_public_key}

  defp parse_private_key(<<kaz_len::32, rest::binary>>) when byte_size(rest) >= kaz_len + 4 do
    <<kaz_sk::binary-size(kaz_len), ml_len::32, rest2::binary>> = rest

    if byte_size(rest2) >= ml_len do
      <<ml_sk::binary-size(ml_len), _::binary>> = rest2
      {:ok, {kaz_sk, ml_sk}}
    else
      {:error, :invalid_private_key}
    end
  end

  defp parse_private_key(_), do: {:error, :invalid_private_key}

  defp parse_signature(<<msg_len::32, rest::binary>>) when byte_size(rest) >= msg_len do
    <<message::binary-size(msg_len), kaz_len::32, rest2::binary>> = rest

    if byte_size(rest2) >= kaz_len do
      <<kaz_sig::binary-size(kaz_len), ml_len::32, ml_sig::binary-size(ml_len), _::binary>> =
        rest2

      {:ok, {message, kaz_sig, ml_sig}}
    else
      {:error, :invalid_signature}
    end
  end

  defp parse_signature(_), do: {:error, :invalid_signature}
end
