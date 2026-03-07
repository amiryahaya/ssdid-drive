defmodule SecureSharing.Crypto do
  @moduledoc """
  Unified cryptographic operations for SecureSharing.

  This module provides a clean API for all cryptographic operations:
  - Post-quantum KEM (Key Encapsulation Mechanism)
  - Post-quantum digital signatures
  - Symmetric encryption (AES-256-GCM)
  - Key derivation (HKDF)
  - Secure random generation

  ## Tenant-Aware Crypto

  Tenants can choose their PQC algorithm suite:
  - `:kaz` - KAZ-KEM + KAZ-SIGN (Malaysian algorithms)
  - `:nist` - ML-KEM-768 + ML-DSA-65 (NIST FIPS 203/204)
  - `:hybrid` - Both combined for defense in depth

  Use the `for_tenant/1` or `for_algorithm/1` functions to get tenant-specific operations:

      # Using tenant struct
      crypto = SecureSharing.Crypto.for_tenant(tenant)
      {:ok, keypair} = crypto.kem_keypair.()

      # Using algorithm directly
      {:ok, keypair} = SecureSharing.Crypto.kem_keypair(:nist)

  ## Configuration

  Configure default providers in config.exs:

      config :secure_sharing, SecureSharing.Crypto,
        kem_provider: SecureSharing.Crypto.Providers.KazKEM,
        sign_provider: SecureSharing.Crypto.Providers.KazSign,
        security_level: 128

  ## Usage

      # Initialize crypto (called by Application supervisor)
      :ok = SecureSharing.Crypto.init()

      # KEM operations (default provider)
      {:ok, keypair} = SecureSharing.Crypto.kem_keypair()

      # KEM operations (specific algorithm)
      {:ok, keypair} = SecureSharing.Crypto.kem_keypair(:nist)
      {:ok, keypair} = SecureSharing.Crypto.kem_keypair(:hybrid)

      # Symmetric encryption
      {:ok, ciphertext} = SecureSharing.Crypto.encrypt(plaintext, key)
      {:ok, plaintext} = SecureSharing.Crypto.decrypt(ciphertext, key)

      # Key derivation
      derived_key = SecureSharing.Crypto.derive_key(ikm, info, length)
  """

  alias SecureSharing.Crypto.Providers.{KazKEM, KazSign, MLKEM, MLDSA, HybridKEM, HybridSign}
  alias SecureSharing.Accounts.Tenant

  @default_security_level 128
  @aes_key_bytes 32
  @aes_nonce_bytes 12
  @aes_tag_bytes 16

  # Provider configuration

  @type pqc_algorithm :: :kaz | :nist | :hybrid

  # Provider mapping by algorithm
  @kem_providers %{
    kaz: KazKEM,
    nist: MLKEM,
    hybrid: HybridKEM
  }

  @sign_providers %{
    kaz: KazSign,
    nist: MLDSA,
    hybrid: HybridSign
  }

  @doc """
  Get the KEM provider module for a specific algorithm.
  """
  @spec kem_provider_for(pqc_algorithm()) :: module()
  def kem_provider_for(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    Map.fetch!(@kem_providers, algorithm)
  end

  @doc """
  Get the signature provider module for a specific algorithm.
  """
  @spec sign_provider_for(pqc_algorithm()) :: module()
  def sign_provider_for(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    Map.fetch!(@sign_providers, algorithm)
  end

  @doc """
  Get the configured default KEM provider module.
  """
  def kem_provider do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Keyword.get(:kem_provider, KazKEM)
  end

  @doc """
  Get the configured default signature provider module.
  """
  def sign_provider do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Keyword.get(:sign_provider, KazSign)
  end

  @doc """
  Get the configured security level.
  """
  def security_level do
    Application.get_env(:secure_sharing, __MODULE__, [])
    |> Keyword.get(:security_level, @default_security_level)
  end

  @doc """
  Get crypto operations configured for a specific tenant.

  Returns a map of functions bound to the tenant's PQC algorithm.
  """
  @spec for_tenant(Tenant.t()) :: map()
  def for_tenant(%Tenant{pqc_algorithm: algorithm}) do
    for_algorithm(algorithm)
  end

  @doc """
  Get crypto operations for a specific PQC algorithm.

  Returns a map of functions bound to the specified algorithm.
  """
  @spec for_algorithm(pqc_algorithm()) :: map()
  def for_algorithm(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    kem = kem_provider_for(algorithm)
    sign = sign_provider_for(algorithm)

    %{
      algorithm: algorithm,
      kem_provider: kem,
      sign_provider: sign,
      kem_keypair: fn -> kem.keypair() end,
      kem_encapsulate: fn pk -> kem.encapsulate(pk) end,
      kem_decapsulate: fn ct, sk -> kem.decapsulate(ct, sk) end,
      sign_keypair: fn -> sign.keypair(security_level()) end,
      sign: fn msg, sk -> sign.sign(security_level(), msg, sk) end,
      verify: fn sig, pk -> sign.verify(security_level(), sig, pk) end
    }
  end

  # Initialization

  @doc """
  Initialize all crypto providers (all algorithms).

  This should be called once during application startup.
  Initializes KAZ, NIST, and Hybrid providers so they're ready for any tenant.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    level = security_level()

    # Initialize all KEM providers
    with :ok <- KazKEM.init(level),
         :ok <- MLKEM.init(level),
         # Initialize all Sign providers
         :ok <- KazSign.init(level),
         :ok <- MLDSA.init(level) do
      # Hybrid providers use KAZ + NIST, so they're ready once the above are initialized
      :ok
    end
  end

  @doc """
  Initialize a specific algorithm's providers.
  """
  @spec init(pqc_algorithm()) :: :ok | {:error, term()}
  def init(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    level = security_level()

    with :ok <- kem_provider_for(algorithm).init(level),
         :ok <- sign_provider_for(algorithm).init(level) do
      :ok
    end
  end

  @doc """
  Cleanup all crypto provider resources.

  Cleans up all initialized providers (KAZ, NIST, Hybrid) to match init/0.
  """
  @spec cleanup() :: :ok
  def cleanup do
    # Cleanup all KEM providers
    KazKEM.cleanup()
    MLKEM.cleanup()

    # Cleanup all Sign providers
    KazSign.cleanup()
    MLDSA.cleanup()

    :ok
  end

  @doc """
  Cleanup a specific algorithm's providers.
  """
  @spec cleanup(pqc_algorithm()) :: :ok
  def cleanup(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    kem_provider_for(algorithm).cleanup()
    sign_provider_for(algorithm).cleanup()
    :ok
  end

  @doc """
  Check if crypto is initialized.
  """
  @spec initialized?() :: boolean()
  def initialized? do
    kem_provider().initialized?() and sign_provider().initialized?()
  end

  # KEM Operations

  @doc """
  Generate a KEM keypair.

  Optionally specify the algorithm (defaults to configured provider).
  """
  @spec kem_keypair() :: {:ok, map()} | {:error, atom()}
  @spec kem_keypair(pqc_algorithm()) :: {:ok, map()} | {:error, atom()}
  def kem_keypair(algorithm \\ nil)

  def kem_keypair(nil), do: kem_provider().keypair()

  def kem_keypair(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    kem_provider_for(algorithm).keypair()
  end

  @doc """
  Encapsulate: Generate a random shared secret and encapsulate it for a recipient.

  Returns `{:ok, %{ciphertext: binary, shared_secret: binary}}` where:
  - `ciphertext` is sent to the recipient
  - `shared_secret` is used locally for encryption (e.g., as a DEK)

  The shared secret is generated by the KEM, not provided by the caller.
  This follows NIST FIPS 203 KEM semantics.

  Optionally specify the algorithm.
  """
  @spec kem_encapsulate(binary()) :: {:ok, map()} | {:error, atom()}
  @spec kem_encapsulate(binary(), pqc_algorithm()) :: {:ok, map()} | {:error, atom()}
  def kem_encapsulate(public_key, algorithm \\ nil)

  def kem_encapsulate(public_key, nil) when is_binary(public_key) and byte_size(public_key) > 0 do
    kem_provider().encapsulate(public_key)
  end

  def kem_encapsulate(public_key, algorithm)
      when is_binary(public_key) and byte_size(public_key) > 0 and
             algorithm in [:kaz, :nist, :hybrid] do
    kem_provider_for(algorithm).encapsulate(public_key)
  end

  def kem_encapsulate(_public_key, _algorithm), do: {:error, :invalid_input}

  @doc """
  Decapsulate: Recover the shared secret from a ciphertext.

  Returns `{:ok, shared_secret}` where `shared_secret` is the same value
  that was returned by `kem_encapsulate/1,2`.

  Optionally specify the algorithm.
  """
  @spec kem_decapsulate(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec kem_decapsulate(binary(), binary(), pqc_algorithm()) :: {:ok, binary()} | {:error, atom()}
  def kem_decapsulate(ciphertext, private_key, algorithm \\ nil)

  def kem_decapsulate(ciphertext, private_key, nil)
      when is_binary(ciphertext) and byte_size(ciphertext) > 0 and
             is_binary(private_key) and byte_size(private_key) > 0 do
    kem_provider().decapsulate(ciphertext, private_key)
  end

  def kem_decapsulate(ciphertext, private_key, algorithm)
      when is_binary(ciphertext) and byte_size(ciphertext) > 0 and
             is_binary(private_key) and byte_size(private_key) > 0 and
             algorithm in [:kaz, :nist, :hybrid] do
    kem_provider_for(algorithm).decapsulate(ciphertext, private_key)
  end

  def kem_decapsulate(_ciphertext, _private_key, _algorithm), do: {:error, :invalid_input}

  # Signature Operations

  @doc """
  Generate a signing keypair.

  Options:
  - No args: uses default provider
  - Algorithm atom (:kaz, :nist, :hybrid): uses that algorithm
  """
  @spec sign_keypair() :: {:ok, map()} | {:error, atom()}
  @spec sign_keypair(pqc_algorithm()) :: {:ok, map()} | {:error, atom()}
  def sign_keypair(algorithm \\ nil)

  def sign_keypair(nil), do: sign_provider().keypair(security_level())

  def sign_keypair(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    sign_provider_for(algorithm).keypair(security_level())
  end

  @doc """
  Sign a message.

  Optionally specify the algorithm.
  """
  @spec sign(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec sign(binary(), binary(), pqc_algorithm()) :: {:ok, binary()} | {:error, atom()}
  def sign(message, private_key, algorithm \\ nil)

  def sign(message, private_key, nil)
      when is_binary(message) and is_binary(private_key) and byte_size(private_key) > 0 do
    sign_provider().sign(security_level(), message, private_key)
  end

  def sign(message, private_key, algorithm)
      when is_binary(message) and is_binary(private_key) and byte_size(private_key) > 0 and
             algorithm in [:kaz, :nist, :hybrid] do
    sign_provider_for(algorithm).sign(security_level(), message, private_key)
  end

  def sign(_message, _private_key, _algorithm), do: {:error, :invalid_input}

  @doc """
  Verify a signature and recover the message.

  Optionally specify the algorithm.
  """
  @spec verify(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec verify(binary(), binary(), pqc_algorithm()) :: {:ok, binary()} | {:error, atom()}
  def verify(signature, public_key, algorithm \\ nil)

  def verify(signature, public_key, nil)
      when is_binary(signature) and byte_size(signature) > 0 and
             is_binary(public_key) and byte_size(public_key) > 0 do
    sign_provider().verify(security_level(), signature, public_key)
  end

  def verify(signature, public_key, algorithm)
      when is_binary(signature) and byte_size(signature) > 0 and
             is_binary(public_key) and byte_size(public_key) > 0 and
             algorithm in [:kaz, :nist, :hybrid] do
    sign_provider_for(algorithm).verify(security_level(), signature, public_key)
  end

  def verify(_signature, _public_key, _algorithm), do: {:error, :invalid_input}

  @doc """
  Check if a signature is valid.

  Optionally specify the algorithm.
  """
  @spec valid_signature?(binary(), binary()) :: boolean()
  @spec valid_signature?(binary(), binary(), pqc_algorithm()) :: boolean()
  def valid_signature?(signature, public_key, algorithm \\ nil)

  def valid_signature?(signature, public_key, nil) do
    provider = sign_provider()

    if function_exported?(provider, :valid?, 3) do
      provider.valid?(security_level(), signature, public_key)
    else
      case verify(signature, public_key) do
        {:ok, _} -> true
        _ -> false
      end
    end
  end

  def valid_signature?(signature, public_key, algorithm)
      when algorithm in [:kaz, :nist, :hybrid] do
    provider = sign_provider_for(algorithm)

    if function_exported?(provider, :valid?, 3) do
      provider.valid?(security_level(), signature, public_key)
    else
      case verify(signature, public_key, algorithm) do
        {:ok, _} -> true
        _ -> false
      end
    end
  end

  # Symmetric Encryption (AES-256-GCM)

  @doc """
  Encrypt plaintext using AES-256-GCM.

  Returns `{:ok, ciphertext}` where ciphertext is: nonce (12 bytes) || tag (16 bytes) || encrypted_data

  ## Parameters

  - `plaintext` - The data to encrypt
  - `key` - 32-byte AES key
  - `aad` - (optional) Additional Authenticated Data

  ## Examples

      key = :crypto.strong_rand_bytes(32)
      {:ok, ciphertext} = SecureSharing.Crypto.encrypt("secret data", key)
      {:ok, plaintext} = SecureSharing.Crypto.decrypt(ciphertext, key)
  """
  @spec encrypt(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec encrypt(binary(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def encrypt(plaintext, key, aad \\ <<>>)

  def encrypt(plaintext, key, aad)
      when is_binary(plaintext) and is_binary(key) and byte_size(key) == @aes_key_bytes do
    nonce = :crypto.strong_rand_bytes(@aes_nonce_bytes)

    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           nonce,
           plaintext,
           aad,
           @aes_tag_bytes,
           true
         ) do
      {ciphertext, tag} ->
        {:ok, nonce <> tag <> ciphertext}

      :error ->
        {:error, :encryption_failed}
    end
  end

  def encrypt(_plaintext, _key, _aad), do: {:error, :invalid_key_size}

  @doc """
  Decrypt ciphertext using AES-256-GCM.

  Expects ciphertext format: nonce (12 bytes) || tag (16 bytes) || encrypted_data

  ## Parameters

  - `ciphertext` - The encrypted data (nonce || tag || data)
  - `key` - 32-byte AES key
  - `aad` - (optional) Additional Authenticated Data (must match encryption)

  ## Examples

      {:ok, plaintext} = SecureSharing.Crypto.decrypt(ciphertext, key)
  """
  @spec decrypt(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec decrypt(binary(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def decrypt(ciphertext, key, aad \\ <<>>)

  def decrypt(ciphertext, key, aad)
      when is_binary(ciphertext) and is_binary(key) and byte_size(key) == @aes_key_bytes do
    min_length = @aes_nonce_bytes + @aes_tag_bytes

    if byte_size(ciphertext) < min_length do
      {:error, :invalid_ciphertext}
    else
      <<nonce::binary-size(@aes_nonce_bytes), tag::binary-size(@aes_tag_bytes),
        encrypted::binary>> =
        ciphertext

      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, encrypted, aad, tag, false) do
        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}

        :error ->
          {:error, :decryption_failed}
      end
    end
  end

  def decrypt(_ciphertext, _key, _aad), do: {:error, :invalid_key_size}

  # Key Derivation (HKDF)

  @doc """
  Derive a key using HKDF (HMAC-based Key Derivation Function).

  Uses SHA-384 as the underlying hash function.

  ## Parameters

  - `ikm` - Input keying material
  - `info` - Context and application specific information
  - `length` - Desired output length in bytes (max 48 * 255 = 12240)
  - `salt` - (optional) Salt value, defaults to 48 zero bytes

  ## Examples

      derived = SecureSharing.Crypto.derive_key(master_key, "encryption-key", 32)
  """
  @spec derive_key(binary(), binary(), non_neg_integer()) :: binary()
  @spec derive_key(binary(), binary(), non_neg_integer(), binary()) :: binary()
  def derive_key(ikm, info, length, salt \\ nil)
      when is_binary(ikm) and is_binary(info) and length > 0 do
    # Use SHA-384 for 192-bit security
    hash_algo = :sha384
    hash_len = 48

    # Default salt is hash_len zero bytes
    actual_salt = salt || :binary.copy(<<0>>, hash_len)

    # Extract
    prk = :crypto.mac(:hmac, hash_algo, actual_salt, ikm)

    # Expand
    hkdf_expand(hash_algo, prk, info, length, hash_len)
  end

  defp hkdf_expand(hash_algo, prk, info, length, hash_len) do
    n = ceil(length / hash_len)

    {okm, _} =
      Enum.reduce(1..n, {<<>>, <<>>}, fn i, {acc, t_prev} ->
        t = :crypto.mac(:hmac, hash_algo, prk, t_prev <> info <> <<i>>)
        {acc <> t, t}
      end)

    binary_part(okm, 0, length)
  end

  # Random Generation

  @doc """
  Generate cryptographically secure random bytes.
  """
  @spec random_bytes(non_neg_integer()) :: binary()
  def random_bytes(length) when is_integer(length) and length > 0 do
    :crypto.strong_rand_bytes(length)
  end

  @doc """
  Generate a random 256-bit (32-byte) key suitable for AES-256.
  """
  @spec generate_key() :: binary()
  def generate_key do
    random_bytes(@aes_key_bytes)
  end

  # Key Wrapping

  @doc """
  Wrap (encrypt) a key using another key.

  This is used for the KEK/DEK hierarchy - wrapping DEKs with KEKs.

  ## Parameters

  - `key_to_wrap` - The key to protect (e.g., DEK)
  - `wrapping_key` - The key to use for wrapping (e.g., KEK)

  ## Returns

  Wrapped key that includes nonce and authentication tag.
  """
  @spec wrap_key(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def wrap_key(key_to_wrap, wrapping_key) do
    encrypt(key_to_wrap, wrapping_key, "key-wrap")
  end

  @doc """
  Unwrap (decrypt) a wrapped key.

  ## Parameters

  - `wrapped_key` - The wrapped key
  - `wrapping_key` - The key used for wrapping
  """
  @spec unwrap_key(binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  def unwrap_key(wrapped_key, wrapping_key) do
    decrypt(wrapped_key, wrapping_key, "key-wrap")
  end

  # Combined Operations (Hybrid encryption for file content)

  @doc """
  Encrypt data using hybrid encryption (KEM + AES-GCM).

  1. KEM encapsulate to generate a shared secret and ciphertext
  2. Use the KEM-generated shared secret as the DEK
  3. Encrypt data with DEK (AES-256-GCM)

  ## Parameters

  - `plaintext` - Data to encrypt
  - `recipient_public_key` - Recipient's KEM public key
  - `algorithm` - (optional) The PQC algorithm (:kaz, :nist, :hybrid)
                  MUST match the algorithm used to generate the public key

  ## Returns

  `{:ok, %{ciphertext: binary, kem_ciphertext: binary}}`

  - `ciphertext` - The AES-encrypted data
  - `kem_ciphertext` - The KEM ciphertext (send to recipient)

  ## Important

  The algorithm parameter MUST match the type of public key provided.
  """
  @spec hybrid_encrypt(binary(), binary()) :: {:ok, map()} | {:error, atom()}
  @spec hybrid_encrypt(binary(), binary(), pqc_algorithm()) :: {:ok, map()} | {:error, atom()}
  def hybrid_encrypt(plaintext, recipient_public_key, algorithm \\ nil)

  def hybrid_encrypt(plaintext, recipient_public_key, nil) do
    # KEM generates the shared secret (DEK) - we don't provide it
    with {:ok, %{ciphertext: kem_ct, shared_secret: dek}} <-
           kem_encapsulate(recipient_public_key),
         {:ok, ciphertext} <- encrypt(plaintext, dek) do
      {:ok, %{ciphertext: ciphertext, kem_ciphertext: kem_ct}}
    end
  end

  def hybrid_encrypt(plaintext, recipient_public_key, algorithm)
      when algorithm in [:kaz, :nist, :hybrid] do
    # KEM generates the shared secret (DEK) - we don't provide it
    with {:ok, %{ciphertext: kem_ct, shared_secret: dek}} <-
           kem_encapsulate(recipient_public_key, algorithm),
         {:ok, ciphertext} <- encrypt(plaintext, dek) do
      {:ok, %{ciphertext: ciphertext, kem_ciphertext: kem_ct}}
    end
  end

  @doc """
  Decrypt data encrypted with hybrid encryption.

  ## Parameters

  - `ciphertext` - The AES-encrypted data
  - `kem_ciphertext` - The KEM ciphertext from encryption
  - `private_key` - Recipient's KEM private key
  - `algorithm` - (optional) The PQC algorithm (:kaz, :nist, :hybrid)
                  MUST match the algorithm used during encryption

  ## Important

  The algorithm parameter MUST match the one used during encryption.
  """
  @spec hybrid_decrypt(binary(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  @spec hybrid_decrypt(binary(), binary(), binary(), pqc_algorithm()) ::
          {:ok, binary()} | {:error, atom()}
  def hybrid_decrypt(ciphertext, kem_ciphertext, private_key, algorithm \\ nil)

  def hybrid_decrypt(ciphertext, kem_ciphertext, private_key, nil) do
    # Recover the shared secret (DEK) via KEM decapsulation
    with {:ok, dek} <- kem_decapsulate(kem_ciphertext, private_key),
         {:ok, plaintext} <- decrypt(ciphertext, dek) do
      {:ok, plaintext}
    end
  end

  def hybrid_decrypt(ciphertext, kem_ciphertext, private_key, algorithm)
      when algorithm in [:kaz, :nist, :hybrid] do
    # Recover the shared secret (DEK) via KEM decapsulation
    with {:ok, dek} <- kem_decapsulate(kem_ciphertext, private_key, algorithm),
         {:ok, plaintext} <- decrypt(ciphertext, dek) do
      {:ok, plaintext}
    end
  end

  # Provider Info

  @doc """
  Get information about the configured crypto providers.
  """
  @spec info() :: map()
  def info do
    %{
      default_kem: %{
        provider: kem_provider(),
        algorithm: kem_provider().algorithm(),
        version: kem_provider().version(),
        initialized: kem_provider().initialized?()
      },
      default_sign: %{
        provider: sign_provider(),
        algorithm: sign_provider().algorithm(),
        version: sign_provider().version(),
        initialized: sign_provider().initialized?()
      },
      security_level: security_level(),
      aes: %{
        algorithm: "AES-256-GCM",
        key_size: @aes_key_bytes,
        nonce_size: @aes_nonce_bytes,
        tag_size: @aes_tag_bytes
      },
      kdf: %{
        algorithm: "HKDF-SHA384"
      },
      available_algorithms: [:kaz, :nist, :hybrid],
      providers: %{
        kaz: %{kem: KazKEM, sign: KazSign},
        nist: %{kem: MLKEM, sign: MLDSA},
        hybrid: %{kem: HybridKEM, sign: HybridSign}
      }
    }
  end

  @doc """
  Get information about a specific algorithm's providers.
  """
  @spec info(pqc_algorithm()) :: map()
  def info(algorithm) when algorithm in [:kaz, :nist, :hybrid] do
    kem = kem_provider_for(algorithm)
    sign = sign_provider_for(algorithm)

    %{
      algorithm: algorithm,
      kem: %{
        provider: kem,
        algorithm: kem.algorithm(),
        version: kem.version(),
        initialized: kem.initialized?()
      },
      sign: %{
        provider: sign,
        algorithm: sign.algorithm(),
        version: sign.version(),
        initialized: sign.initialized?()
      }
    }
  end
end
