defmodule SecureSharing.Crypto.Providers.HybridKEM do
  @moduledoc """
  Hybrid KEM provider combining KAZ-KEM and ML-KEM for defense in depth.

  This provider encapsulates using BOTH algorithms and combines their
  shared secrets. An attacker would need to break BOTH algorithms to
  recover the combined shared secret.

  ## Security Model

  The combined shared secret is derived as:
  ```
  combined_ss = HKDF(kaz_ss || ml_ss, "hybrid-kem-combined-secret", 32)
  ```

  This ensures that even if one algorithm is compromised, the combined
  secret remains secure as long as the other algorithm is sound.

  ## True KEM Semantics

  - `encapsulate(pk)` generates shared secrets from both algorithms,
    combines them via HKDF, and returns the combined ciphertext
  - `decapsulate(ct, sk)` recovers both shared secrets and derives
    the same combined secret
  """

  @behaviour SecureSharing.Crypto.KEMProvider

  alias SecureSharing.Crypto.Providers.{KazKEM, MLKEM}

  @impl true
  def init(level \\ 128) do
    with :ok <- KazKEM.init(level),
         :ok <- MLKEM.init(level) do
      :ok
    end
  end

  @impl true
  def initialized? do
    KazKEM.initialized?() and MLKEM.initialized?()
  end

  @impl true
  def get_level do
    # Return the higher security level (hybrid provides at least this)
    KazKEM.get_level()
  end

  @impl true
  def get_sizes do
    with {:ok, kaz_sizes} <- KazKEM.get_sizes(),
         {:ok, ml_sizes} <- MLKEM.get_sizes() do
      {:ok,
       %{
         # +8 for length prefixes
         public_key: kaz_sizes.public_key + ml_sizes.public_key + 8,
         private_key: kaz_sizes.private_key + ml_sizes.private_key + 8,
         ciphertext: kaz_sizes.ciphertext + ml_sizes.ciphertext + 8,
         # Combined shared secret is always 32 bytes
         shared_secret: 32
       }}
    end
  end

  @impl true
  def keypair do
    with {:ok, kaz_keypair} <- KazKEM.keypair(),
         {:ok, ml_keypair} <- MLKEM.keypair() do
      # Combine keypairs with length prefixes
      kaz_pub_len = byte_size(kaz_keypair.public_key)
      kaz_priv_len = byte_size(kaz_keypair.private_key)

      public_key =
        <<kaz_pub_len::32, kaz_keypair.public_key::binary, byte_size(ml_keypair.public_key)::32,
          ml_keypair.public_key::binary>>

      private_key =
        <<kaz_priv_len::32, kaz_keypair.private_key::binary,
          byte_size(ml_keypair.private_key)::32, ml_keypair.private_key::binary>>

      {:ok, %{public_key: public_key, private_key: private_key}}
    end
  end

  @impl true
  def encapsulate(combined_public_key) do
    with {:ok, {kaz_pk, ml_pk}} <- parse_public_key(combined_public_key),
         # Encapsulate with both algorithms - each generates its own shared secret
         {:ok, %{ciphertext: kaz_ct, shared_secret: kaz_ss}} <- KazKEM.encapsulate(kaz_pk),
         {:ok, %{ciphertext: ml_ct, shared_secret: ml_ss}} <- MLKEM.encapsulate(ml_pk) do
      # Combine shared secrets using HKDF for defense in depth
      combined_ss = derive_combined_secret(kaz_ss, ml_ss)

      # Build combined ciphertext with length prefixes
      ciphertext =
        <<byte_size(kaz_ct)::32, kaz_ct::binary, byte_size(ml_ct)::32, ml_ct::binary>>

      {:ok, %{ciphertext: ciphertext, shared_secret: combined_ss}}
    end
  end

  @impl true
  def decapsulate(combined_ciphertext, combined_private_key) do
    with {:ok, {kaz_sk, ml_sk}} <- parse_private_key(combined_private_key),
         {:ok, {kaz_ct, ml_ct}} <- parse_ciphertext(combined_ciphertext),
         # Decapsulate with both algorithms
         {:ok, kaz_ss} <- KazKEM.decapsulate(kaz_ct, kaz_sk),
         {:ok, ml_ss} <- MLKEM.decapsulate(ml_ct, ml_sk) do
      # Derive the same combined secret
      combined_ss = derive_combined_secret(kaz_ss, ml_ss)
      {:ok, combined_ss}
    end
  end

  @impl true
  def cleanup do
    KazKEM.cleanup()
    MLKEM.cleanup()
    :ok
  end

  @impl true
  def version do
    {:ok, {ml_version, _}} = MLKEM.version()
    "#{KazKEM.version()}+#{ml_version}"
  end

  @impl true
  def algorithm do
    "Hybrid(KAZ-KEM+ML-KEM-768)"
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

  defp parse_ciphertext(<<kaz_len::32, rest::binary>>) when byte_size(rest) >= kaz_len do
    <<kaz_ct::binary-size(kaz_len), ml_len::32, rest2::binary>> = rest

    if byte_size(rest2) >= ml_len do
      <<ml_ct::binary-size(ml_len), _rest3::binary>> = rest2
      {:ok, {kaz_ct, ml_ct}}
    else
      {:error, :invalid_ciphertext}
    end
  end

  defp parse_ciphertext(_), do: {:error, :invalid_ciphertext}

  defp derive_combined_secret(kaz_ss, ml_ss) do
    # Use HKDF to combine the two shared secrets
    # This provides defense in depth - both must be compromised
    ikm = kaz_ss <> ml_ss
    info = "hybrid-kem-combined-secret"
    SecureSharing.Crypto.derive_key(ikm, info, 32)
  end
end
