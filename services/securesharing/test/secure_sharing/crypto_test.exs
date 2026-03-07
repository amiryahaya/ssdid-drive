defmodule SecureSharing.CryptoTest do
  use ExUnit.Case, async: false

  alias SecureSharing.Crypto

  # Initialize crypto once for all tests
  setup_all do
    :ok = Crypto.init()
    on_exit(fn -> Crypto.cleanup() end)
    :ok
  end

  describe "initialization" do
    test "crypto is initialized" do
      assert Crypto.initialized?()
    end

    test "info returns provider details" do
      info = Crypto.info()

      assert info.default_kem.algorithm == "KAZ-KEM"
      assert info.default_sign.algorithm == "KAZ-SIGN"
      assert info.security_level == 128
      assert info.aes.algorithm == "AES-256-GCM"
      assert info.kdf.algorithm == "HKDF-SHA384"
      assert :kaz in info.available_algorithms
      assert :nist in info.available_algorithms
      assert :hybrid in info.available_algorithms
    end
  end

  describe "KEM operations" do
    test "keypair/0 generates a keypair" do
      {:ok, keypair} = Crypto.kem_keypair()

      assert is_binary(keypair.public_key)
      assert is_binary(keypair.private_key)
      assert byte_size(keypair.public_key) > 0
      assert byte_size(keypair.private_key) > 0
    end

    test "encapsulate/decapsulate round-trip" do
      {:ok, keypair} = Crypto.kem_keypair()

      # KEM generates the shared secret internally
      {:ok, %{ciphertext: ciphertext, shared_secret: shared_secret}} =
        Crypto.kem_encapsulate(keypair.public_key)

      assert is_binary(ciphertext)
      assert is_binary(shared_secret)
      assert byte_size(shared_secret) == 32

      {:ok, recovered} = Crypto.kem_decapsulate(ciphertext, keypair.private_key)
      assert recovered == shared_secret
    end

    test "decapsulate fails with wrong private key" do
      {:ok, keypair1} = Crypto.kem_keypair()
      {:ok, keypair2} = Crypto.kem_keypair()

      {:ok, %{ciphertext: ciphertext, shared_secret: shared_secret}} =
        Crypto.kem_encapsulate(keypair1.public_key)

      {:ok, recovered} = Crypto.kem_decapsulate(ciphertext, keypair2.private_key)

      # Wrong key should produce different result
      refute recovered == shared_secret
    end
  end

  describe "signature operations" do
    test "sign_keypair/0 generates a keypair" do
      {:ok, keypair} = Crypto.sign_keypair()

      assert is_binary(keypair.public_key)
      assert is_binary(keypair.private_key)
      assert byte_size(keypair.public_key) > 0
      assert byte_size(keypair.private_key) > 0
    end

    test "sign/verify round-trip" do
      {:ok, keypair} = Crypto.sign_keypair()
      message = "Hello, SecureSharing!"

      {:ok, signature} = Crypto.sign(message, keypair.private_key)
      assert is_binary(signature)

      {:ok, recovered} = Crypto.verify(signature, keypair.public_key)
      assert recovered == message
    end

    test "valid_signature?/2 returns true for valid signature" do
      {:ok, keypair} = Crypto.sign_keypair()
      message = "Test message"

      {:ok, signature} = Crypto.sign(message, keypair.private_key)
      assert Crypto.valid_signature?(signature, keypair.public_key)
    end

    test "verify fails with wrong public key" do
      {:ok, keypair1} = Crypto.sign_keypair()
      {:ok, keypair2} = Crypto.sign_keypair()
      message = "Test message"

      {:ok, signature} = Crypto.sign(message, keypair1.private_key)

      # Verification with wrong key should fail
      assert {:error, _} = Crypto.verify(signature, keypair2.public_key)
      refute Crypto.valid_signature?(signature, keypair2.public_key)
    end
  end

  describe "AES-256-GCM encryption" do
    test "encrypt/decrypt round-trip" do
      key = Crypto.generate_key()
      plaintext = "Secret data to encrypt"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key)
      assert is_binary(ciphertext)
      assert ciphertext != plaintext

      {:ok, decrypted} = Crypto.decrypt(ciphertext, key)
      assert decrypted == plaintext
    end

    test "encrypt/decrypt with AAD" do
      key = Crypto.generate_key()
      plaintext = "Secret data"
      aad = "additional authenticated data"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key, aad)
      {:ok, decrypted} = Crypto.decrypt(ciphertext, key, aad)
      assert decrypted == plaintext
    end

    test "decrypt fails with wrong key" do
      key1 = Crypto.generate_key()
      key2 = Crypto.generate_key()
      plaintext = "Secret data"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key1)
      assert {:error, :decryption_failed} = Crypto.decrypt(ciphertext, key2)
    end

    test "decrypt fails with wrong AAD" do
      key = Crypto.generate_key()
      plaintext = "Secret data"
      aad1 = "correct aad"
      aad2 = "wrong aad"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key, aad1)
      assert {:error, :decryption_failed} = Crypto.decrypt(ciphertext, key, aad2)
    end

    test "decrypt fails with modified ciphertext" do
      key = Crypto.generate_key()
      plaintext = "Secret data"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key)

      # Modify a byte in the tag portion (bytes 12-27) to corrupt authentication
      # Format: nonce (12 bytes) + tag (16 bytes) + encrypted_data
      # XOR the byte to ensure it's always changed
      <<nonce::binary-size(12), tag_head::binary-size(8), byte, tag_rest::binary-size(7),
        encrypted::binary>> = ciphertext

      modified = nonce <> tag_head <> <<Bitwise.bxor(byte, 0xFF)>> <> tag_rest <> encrypted

      assert {:error, :decryption_failed} = Crypto.decrypt(modified, key)
    end

    test "encrypt fails with invalid key size" do
      # Too short
      bad_key = :crypto.strong_rand_bytes(16)
      assert {:error, :invalid_key_size} = Crypto.encrypt("data", bad_key)
    end

    test "ciphertext format includes nonce and tag" do
      key = Crypto.generate_key()
      plaintext = "Test"

      {:ok, ciphertext} = Crypto.encrypt(plaintext, key)

      # Format: nonce (12) + tag (16) + encrypted_data
      assert byte_size(ciphertext) >= 12 + 16 + byte_size(plaintext)
    end
  end

  describe "key derivation (HKDF)" do
    test "derive_key produces deterministic output" do
      ikm = :crypto.strong_rand_bytes(32)
      info = "test-context"

      key1 = Crypto.derive_key(ikm, info, 32)
      key2 = Crypto.derive_key(ikm, info, 32)

      assert key1 == key2
      assert byte_size(key1) == 32
    end

    test "derive_key with different info produces different keys" do
      ikm = :crypto.strong_rand_bytes(32)

      key1 = Crypto.derive_key(ikm, "context-1", 32)
      key2 = Crypto.derive_key(ikm, "context-2", 32)

      refute key1 == key2
    end

    test "derive_key with salt" do
      ikm = :crypto.strong_rand_bytes(32)
      info = "test"
      salt = :crypto.strong_rand_bytes(48)

      key_with_salt = Crypto.derive_key(ikm, info, 32, salt)
      key_without_salt = Crypto.derive_key(ikm, info, 32)

      refute key_with_salt == key_without_salt
    end

    test "derive_key can produce various lengths" do
      ikm = :crypto.strong_rand_bytes(32)

      key16 = Crypto.derive_key(ikm, "test", 16)
      key32 = Crypto.derive_key(ikm, "test", 32)
      key64 = Crypto.derive_key(ikm, "test", 64)

      assert byte_size(key16) == 16
      assert byte_size(key32) == 32
      assert byte_size(key64) == 64

      # Shorter keys should be prefix of longer ones
      assert key16 == binary_part(key32, 0, 16)
      assert key32 == binary_part(key64, 0, 32)
    end
  end

  describe "key wrapping" do
    test "wrap_key/unwrap_key round-trip" do
      kek = Crypto.generate_key()
      dek = Crypto.generate_key()

      {:ok, wrapped} = Crypto.wrap_key(dek, kek)
      {:ok, unwrapped} = Crypto.unwrap_key(wrapped, kek)

      assert unwrapped == dek
    end

    test "unwrap fails with wrong wrapping key" do
      kek1 = Crypto.generate_key()
      kek2 = Crypto.generate_key()
      dek = Crypto.generate_key()

      {:ok, wrapped} = Crypto.wrap_key(dek, kek1)
      assert {:error, :decryption_failed} = Crypto.unwrap_key(wrapped, kek2)
    end
  end

  describe "hybrid encryption" do
    test "hybrid_encrypt/hybrid_decrypt round-trip" do
      {:ok, keypair} = Crypto.kem_keypair()
      plaintext = "Secret file content that needs hybrid encryption"

      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair.public_key)
      assert is_binary(encrypted.ciphertext)
      assert is_binary(encrypted.kem_ciphertext)

      {:ok, decrypted} =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          keypair.private_key
        )

      assert decrypted == plaintext
    end

    test "hybrid encryption works with large data" do
      {:ok, keypair} = Crypto.kem_keypair()
      # 1MB of random data
      plaintext = :crypto.strong_rand_bytes(1024 * 1024)

      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair.public_key)

      {:ok, decrypted} =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          keypair.private_key
        )

      assert decrypted == plaintext
    end

    test "hybrid decrypt fails with wrong private key" do
      {:ok, keypair1} = Crypto.kem_keypair()
      {:ok, keypair2} = Crypto.kem_keypair()
      plaintext = "Secret data"

      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair1.public_key)

      # Decryption with wrong key should fail or produce wrong result
      result =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          keypair2.private_key
        )

      case result do
        {:error, _} -> assert true
        {:ok, decrypted} -> refute decrypted == plaintext
      end
    end

    test "hybrid encryption with NIST algorithm" do
      {:ok, keypair} = Crypto.kem_keypair(:nist)
      plaintext = "Secret data for NIST encryption"

      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair.public_key, :nist)

      {:ok, decrypted} =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          keypair.private_key,
          :nist
        )

      assert decrypted == plaintext
    end

    test "hybrid encryption with Hybrid algorithm" do
      {:ok, keypair} = Crypto.kem_keypair(:hybrid)
      plaintext = "Secret data for Hybrid encryption"

      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair.public_key, :hybrid)

      {:ok, decrypted} =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          keypair.private_key,
          :hybrid
        )

      assert decrypted == plaintext
    end

    test "hybrid encryption algorithm mismatch fails" do
      # Generate KAZ keypair
      {:ok, kaz_keypair} = Crypto.kem_keypair(:kaz)
      plaintext = "Secret data"

      # Encrypt with KAZ
      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, kaz_keypair.public_key, :kaz)

      # Trying to decrypt with NIST algorithm should fail
      result =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          kaz_keypair.private_key,
          :nist
        )

      assert {:error, _} = result
    end
  end

  describe "random generation" do
    test "random_bytes generates specified length" do
      bytes16 = Crypto.random_bytes(16)
      bytes32 = Crypto.random_bytes(32)

      assert byte_size(bytes16) == 16
      assert byte_size(bytes32) == 32
    end

    test "random_bytes generates unique values" do
      bytes1 = Crypto.random_bytes(32)
      bytes2 = Crypto.random_bytes(32)

      refute bytes1 == bytes2
    end

    test "generate_key produces 32-byte key" do
      key = Crypto.generate_key()
      assert byte_size(key) == 32
    end
  end

  describe "multi-algorithm support" do
    test "NIST KEM operations" do
      {:ok, keypair} = Crypto.kem_keypair(:nist)
      assert is_binary(keypair.public_key)
      # ML-KEM-768
      assert byte_size(keypair.public_key) == 1184

      # NIST encapsulate generates its own shared secret
      {:ok, %{ciphertext: ciphertext, shared_secret: shared_secret}} =
        Crypto.kem_encapsulate(keypair.public_key, :nist)

      assert is_binary(ciphertext)
      assert is_binary(shared_secret)
      assert byte_size(shared_secret) == 32

      {:ok, recovered} = Crypto.kem_decapsulate(ciphertext, keypair.private_key, :nist)
      assert recovered == shared_secret
    end

    test "NIST signature operations" do
      {:ok, keypair} = Crypto.sign_keypair(:nist)
      assert is_binary(keypair.public_key)
      # ML-DSA-65
      assert byte_size(keypair.public_key) == 1952

      message = "Test message for NIST signatures"
      {:ok, signature} = Crypto.sign(message, keypair.private_key, :nist)
      assert is_binary(signature)

      {:ok, recovered} = Crypto.verify(signature, keypair.public_key, :nist)
      assert recovered == message
    end

    test "KAZ algorithm selection" do
      {:ok, kem_keypair} = Crypto.kem_keypair(:kaz)
      {:ok, sign_keypair} = Crypto.sign_keypair(:kaz)

      assert is_binary(kem_keypair.public_key)
      assert is_binary(sign_keypair.public_key)

      # KAZ encapsulate/decapsulate (KEM generates the shared secret)
      {:ok, %{ciphertext: ct, shared_secret: shared_secret}} =
        Crypto.kem_encapsulate(kem_keypair.public_key, :kaz)

      {:ok, recovered} = Crypto.kem_decapsulate(ct, kem_keypair.private_key, :kaz)
      assert recovered == shared_secret

      # KAZ sign/verify
      message = "KAZ test"
      {:ok, sig} = Crypto.sign(message, sign_keypair.private_key, :kaz)
      {:ok, msg} = Crypto.verify(sig, sign_keypair.public_key, :kaz)
      assert msg == message
    end

    test "info returns details for specific algorithm" do
      nist_info = Crypto.info(:nist)
      assert nist_info.algorithm == :nist
      assert nist_info.kem.algorithm == "ML-KEM-768"
      assert nist_info.sign.algorithm == "ML-DSA-65"

      kaz_info = Crypto.info(:kaz)
      assert kaz_info.algorithm == :kaz
      assert kaz_info.kem.algorithm == "KAZ-KEM"
      assert kaz_info.sign.algorithm == "KAZ-SIGN"
    end

    test "for_algorithm returns bound functions" do
      nist = Crypto.for_algorithm(:nist)

      assert nist.algorithm == :nist
      {:ok, keypair} = nist.kem_keypair.()
      assert byte_size(keypair.public_key) == 1184
    end
  end

  describe "tenant-based crypto" do
    test "for_tenant uses tenant's algorithm" do
      tenant = %SecureSharing.Accounts.Tenant{
        id: "test-id",
        name: "Test",
        slug: "test",
        pqc_algorithm: :nist
      }

      crypto = Crypto.for_tenant(tenant)
      assert crypto.algorithm == :nist
      assert crypto.kem_provider == SecureSharing.Crypto.Providers.MLKEM
      assert crypto.sign_provider == SecureSharing.Crypto.Providers.MLDSA
    end
  end

  describe "hybrid signature operations" do
    test "sign_keypair(:hybrid) generates combined keypair" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)

      assert is_binary(keypair.public_key)
      assert is_binary(keypair.private_key)

      # Hybrid keys should be larger than individual algorithm keys
      # KAZ-SIGN public key + ML-DSA-65 public key + length prefixes
      {:ok, kaz_keypair} = Crypto.sign_keypair(:kaz)
      {:ok, nist_keypair} = Crypto.sign_keypair(:nist)

      # Hybrid public key = 4 bytes (kaz_len) + kaz_pk + 4 bytes (ml_len) + ml_pk
      expected_min_size =
        byte_size(kaz_keypair.public_key) + byte_size(nist_keypair.public_key) + 8

      assert byte_size(keypair.public_key) >= expected_min_size

      # Same for private key
      expected_min_priv_size =
        byte_size(kaz_keypair.private_key) + byte_size(nist_keypair.private_key) + 8

      assert byte_size(keypair.private_key) >= expected_min_priv_size
    end

    test "sign/verify round-trip with :hybrid algorithm" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)
      message = "Test message for hybrid signatures"

      {:ok, signature} = Crypto.sign(message, keypair.private_key, :hybrid)
      assert is_binary(signature)

      {:ok, recovered} = Crypto.verify(signature, keypair.public_key, :hybrid)
      assert recovered == message
    end

    test "hybrid signature verify fails with wrong key" do
      {:ok, keypair1} = Crypto.sign_keypair(:hybrid)
      {:ok, keypair2} = Crypto.sign_keypair(:hybrid)
      message = "Test message"

      {:ok, signature} = Crypto.sign(message, keypair1.private_key, :hybrid)

      # Verification with wrong key should fail
      assert {:error, _} = Crypto.verify(signature, keypair2.public_key, :hybrid)
      refute Crypto.valid_signature?(signature, keypair2.public_key, :hybrid)
    end

    test "hybrid signature with KAZ-only key fails" do
      {:ok, kaz_keypair} = Crypto.sign_keypair(:kaz)
      {:ok, hybrid_keypair} = Crypto.sign_keypair(:hybrid)
      message = "Test message"

      # Sign with hybrid
      {:ok, hybrid_signature} = Crypto.sign(message, hybrid_keypair.private_key, :hybrid)

      # Trying to verify hybrid signature with KAZ-only key should fail
      # (key format mismatch - KAZ key lacks length prefixes and ML-DSA component)
      assert {:error, _} = Crypto.verify(hybrid_signature, kaz_keypair.public_key, :hybrid)

      # Sign with KAZ
      {:ok, kaz_signature} = Crypto.sign(message, kaz_keypair.private_key, :kaz)

      # Trying to verify KAZ signature with hybrid key should fail
      # (signature format mismatch - KAZ signature lacks ML-DSA component)
      assert {:error, _} = Crypto.verify(kaz_signature, hybrid_keypair.public_key, :hybrid)
    end

    test "hybrid signature format includes both signatures" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)
      message = "Test message for signature format"

      {:ok, signature} = Crypto.sign(message, keypair.private_key, :hybrid)

      # Hybrid signature format: msg_len(32) + message + kaz_sig_len(32) + kaz_sig + ml_sig_len(32) + ml_sig
      # Parse to verify structure
      <<msg_len::32, rest::binary>> = signature
      assert msg_len == byte_size(message)

      <<embedded_msg::binary-size(msg_len), kaz_sig_len::32, rest2::binary>> = rest
      assert embedded_msg == message

      <<_kaz_sig::binary-size(kaz_sig_len), ml_sig_len::32, ml_sig::binary-size(ml_sig_len),
        _::binary>> = rest2

      # ML-DSA-65 signature is 3309 bytes
      assert ml_sig_len == 3309
      assert byte_size(ml_sig) == 3309
    end

    test "hybrid valid_signature? returns true for valid signature" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)
      message = "Test message"

      {:ok, signature} = Crypto.sign(message, keypair.private_key, :hybrid)
      assert Crypto.valid_signature?(signature, keypair.public_key, :hybrid)
    end

    test "hybrid signature with empty message" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)
      message = ""

      {:ok, signature} = Crypto.sign(message, keypair.private_key, :hybrid)
      {:ok, recovered} = Crypto.verify(signature, keypair.public_key, :hybrid)
      assert recovered == message
    end

    @tag :nif_behavior
    test "hybrid signature with large message" do
      {:ok, keypair} = Crypto.sign_keypair(:hybrid)
      # 1MB message
      message = :crypto.strong_rand_bytes(1024 * 1024)

      {:ok, signature} = Crypto.sign(message, keypair.private_key, :hybrid)
      {:ok, recovered} = Crypto.verify(signature, keypair.public_key, :hybrid)
      assert recovered == message
    end

    test "hybrid info returns correct algorithm details" do
      hybrid_info = Crypto.info(:hybrid)

      assert hybrid_info.algorithm == :hybrid
      assert hybrid_info.sign.algorithm == "Hybrid(KAZ-SIGN+ML-DSA-65)"
      assert hybrid_info.kem.algorithm == "Hybrid(KAZ-KEM+ML-KEM-768)"
    end

    test "for_algorithm(:hybrid) returns bound functions" do
      hybrid = Crypto.for_algorithm(:hybrid)

      assert hybrid.algorithm == :hybrid
      {:ok, keypair} = hybrid.sign_keypair.()

      # Verify it's a hybrid keypair by checking size
      {:ok, kaz_keypair} = Crypto.sign_keypair(:kaz)
      {:ok, nist_keypair} = Crypto.sign_keypair(:nist)

      expected_min_size =
        byte_size(kaz_keypair.public_key) + byte_size(nist_keypair.public_key) + 8

      assert byte_size(keypair.public_key) >= expected_min_size
    end
  end

  describe "NIF error handling" do
    test "handles nil input gracefully" do
      # KEM encapsulate with nil public key
      assert {:error, _} = Crypto.kem_encapsulate(nil)
      assert {:error, _} = Crypto.kem_encapsulate(nil, :kaz)
      assert {:error, _} = Crypto.kem_encapsulate(nil, :nist)
      assert {:error, _} = Crypto.kem_encapsulate(nil, :hybrid)

      # KEM decapsulate with nil inputs
      {:ok, keypair} = Crypto.kem_keypair()
      {:ok, %{ciphertext: ciphertext}} = Crypto.kem_encapsulate(keypair.public_key)

      assert {:error, _} = Crypto.kem_decapsulate(nil, keypair.private_key)
      assert {:error, _} = Crypto.kem_decapsulate(ciphertext, nil)
      assert {:error, _} = Crypto.kem_decapsulate(nil, nil)

      # Sign with nil inputs
      {:ok, sign_keypair} = Crypto.sign_keypair()
      assert {:error, _} = Crypto.sign(nil, sign_keypair.private_key)
      assert {:error, _} = Crypto.sign("message", nil)
      assert {:error, _} = Crypto.sign(nil, nil)

      # Verify with nil inputs
      {:ok, signature} = Crypto.sign("test", sign_keypair.private_key)
      assert {:error, _} = Crypto.verify(nil, sign_keypair.public_key)
      assert {:error, _} = Crypto.verify(signature, nil)
      assert {:error, _} = Crypto.verify(nil, nil)

      # AES encryption with nil
      key = Crypto.generate_key()
      assert {:error, _} = Crypto.encrypt(nil, key)
      assert {:error, _} = Crypto.encrypt("data", nil)
      assert {:error, _} = Crypto.decrypt(nil, key)
      assert {:error, _} = Crypto.decrypt("ciphertext", nil)
    end

    test "handles empty binary input" do
      # KEM encapsulate with empty public key should fail
      assert {:error, _} = Crypto.kem_encapsulate(<<>>)
      assert {:error, _} = Crypto.kem_encapsulate(<<>>, :kaz)
      assert {:error, _} = Crypto.kem_encapsulate(<<>>, :nist)

      # KEM decapsulate with empty inputs
      {:ok, keypair} = Crypto.kem_keypair()
      {:ok, %{ciphertext: ciphertext}} = Crypto.kem_encapsulate(keypair.public_key)

      assert {:error, _} = Crypto.kem_decapsulate(<<>>, keypair.private_key)
      assert {:error, _} = Crypto.kem_decapsulate(ciphertext, <<>>)

      # Sign with empty private key should fail
      assert {:error, _} = Crypto.sign("message", <<>>)

      # Verify with empty inputs should fail
      {:ok, sign_keypair} = Crypto.sign_keypair()
      {:ok, signature} = Crypto.sign("test", sign_keypair.private_key)
      assert {:error, _} = Crypto.verify(<<>>, sign_keypair.public_key)
      assert {:error, _} = Crypto.verify(signature, <<>>)

      # Empty message signing should work (valid edge case)
      {:ok, empty_sig} = Crypto.sign(<<>>, sign_keypair.private_key)
      {:ok, recovered} = Crypto.verify(empty_sig, sign_keypair.public_key)
      assert recovered == <<>>

      # AES with empty key should fail
      assert {:error, _} = Crypto.encrypt("data", <<>>)
      assert {:error, _} = Crypto.decrypt("data", <<>>)

      # AES with empty plaintext should work
      key = Crypto.generate_key()
      {:ok, ciphertext} = Crypto.encrypt(<<>>, key)
      {:ok, decrypted} = Crypto.decrypt(ciphertext, key)
      assert decrypted == <<>>
    end

    @tag :nif_behavior
    test "handles extremely large input" do
      # Test with 10MB of data - should work but may be slow
      large_data = :crypto.strong_rand_bytes(10 * 1024 * 1024)

      # AES encryption with large data
      key = Crypto.generate_key()
      {:ok, ciphertext} = Crypto.encrypt(large_data, key)
      {:ok, decrypted} = Crypto.decrypt(ciphertext, key)
      assert decrypted == large_data

      # Signing large data
      {:ok, sign_keypair} = Crypto.sign_keypair()
      {:ok, signature} = Crypto.sign(large_data, sign_keypair.private_key)
      {:ok, recovered} = Crypto.verify(signature, sign_keypair.public_key)
      assert recovered == large_data

      # Hybrid encryption with large data
      {:ok, kem_keypair} = Crypto.kem_keypair()
      {:ok, encrypted} = Crypto.hybrid_encrypt(large_data, kem_keypair.public_key)

      {:ok, hybrid_decrypted} =
        Crypto.hybrid_decrypt(
          encrypted.ciphertext,
          encrypted.kem_ciphertext,
          kem_keypair.private_key
        )

      assert hybrid_decrypted == large_data
    end

    @tag :nif_behavior
    test "handles malformed key inputs" do
      # Generate valid keypairs for comparison
      {:ok, kem_keypair} = Crypto.kem_keypair()
      {:ok, sign_keypair} = Crypto.sign_keypair()

      # Truncated keys (half the size)
      truncated_kem_pk =
        binary_part(kem_keypair.public_key, 0, div(byte_size(kem_keypair.public_key), 2))

      truncated_sign_pk =
        binary_part(sign_keypair.public_key, 0, div(byte_size(sign_keypair.public_key), 2))

      # KEM encapsulate with truncated key should fail
      assert {:error, _} = Crypto.kem_encapsulate(truncated_kem_pk)

      # Sign works but verify with truncated key should fail
      {:ok, signature} = Crypto.sign("test", sign_keypair.private_key)
      assert {:error, _} = Crypto.verify(signature, truncated_sign_pk)

      # Random garbage as keys
      garbage = :crypto.strong_rand_bytes(100)
      assert {:error, _} = Crypto.kem_encapsulate(garbage)
      assert {:error, _} = Crypto.verify(signature, garbage)
    end

    @tag :nif_behavior
    test "handles corrupted ciphertext/signature" do
      {:ok, kem_keypair} = Crypto.kem_keypair()
      {:ok, sign_keypair} = Crypto.sign_keypair()

      # Valid signature
      {:ok, signature} = Crypto.sign("test message", sign_keypair.private_key)

      # Corrupt one byte in the signature
      sig_size = byte_size(signature)
      corrupt_pos = div(sig_size, 2)
      <<head::binary-size(corrupt_pos), _byte, tail::binary>> = signature
      corrupted_sig = head <> <<0xFF>> <> tail

      # Verification should fail
      assert {:error, _} = Crypto.verify(corrupted_sig, sign_keypair.public_key)

      # Valid KEM ciphertext
      {:ok, %{ciphertext: ct, shared_secret: ss}} = Crypto.kem_encapsulate(kem_keypair.public_key)

      # Corrupt the ciphertext
      ct_size = byte_size(ct)
      corrupt_ct_pos = div(ct_size, 2)
      <<ct_head::binary-size(corrupt_ct_pos), _ct_byte, ct_tail::binary>> = ct
      corrupted_ct = ct_head <> <<0xFF>> <> ct_tail

      # Decapsulation should produce different result (or error depending on algorithm)
      result = Crypto.kem_decapsulate(corrupted_ct, kem_keypair.private_key)

      case result do
        {:error, _} -> assert true
        {:ok, recovered_ss} -> refute recovered_ss == ss
      end
    end

    @tag :nif_behavior
    test "handles algorithm mismatch in operations" do
      # Generate keys for different algorithms
      {:ok, kaz_kem_keypair} = Crypto.kem_keypair(:kaz)
      {:ok, nist_kem_keypair} = Crypto.kem_keypair(:nist)
      {:ok, kaz_sign_keypair} = Crypto.sign_keypair(:kaz)
      {:ok, nist_sign_keypair} = Crypto.sign_keypair(:nist)

      # Encapsulate with KAZ, try to decapsulate specifying NIST algorithm
      {:ok, %{ciphertext: kaz_ct}} = Crypto.kem_encapsulate(kaz_kem_keypair.public_key, :kaz)
      assert {:error, _} = Crypto.kem_decapsulate(kaz_ct, kaz_kem_keypair.private_key, :nist)

      # Sign with KAZ, try to verify specifying NIST algorithm
      {:ok, kaz_sig} = Crypto.sign("test", kaz_sign_keypair.private_key, :kaz)
      assert {:error, _} = Crypto.verify(kaz_sig, kaz_sign_keypair.public_key, :nist)

      # Cross-algorithm key usage (KAZ key with NIST operation)
      assert {:error, _} = Crypto.kem_encapsulate(kaz_kem_keypair.public_key, :nist)
      assert {:error, _} = Crypto.verify(kaz_sig, nist_sign_keypair.public_key, :nist)
    end
  end

  describe "key size validation" do
    test "encrypt fails with empty key" do
      plaintext = "secret data"

      # Empty key should fail
      assert {:error, _} = Crypto.encrypt(plaintext, <<>>)

      # Key too short (16 bytes instead of 32)
      short_key = :crypto.strong_rand_bytes(16)
      assert {:error, :invalid_key_size} = Crypto.encrypt(plaintext, short_key)

      # Key too long (64 bytes instead of 32)
      long_key = :crypto.strong_rand_bytes(64)
      assert {:error, :invalid_key_size} = Crypto.encrypt(plaintext, long_key)

      # Correct size works
      valid_key = Crypto.generate_key()
      assert {:ok, _} = Crypto.encrypt(plaintext, valid_key)
    end

    @tag :nif_behavior
    test "kem_encapsulate fails with malformed public key" do
      # Get valid key sizes for reference
      {:ok, valid_keypair} = Crypto.kem_keypair(:kaz)
      valid_pk_size = byte_size(valid_keypair.public_key)

      # Key too short (half size) - should fail
      short_key = :crypto.strong_rand_bytes(div(valid_pk_size, 2))
      assert {:error, _} = Crypto.kem_encapsulate(short_key, :kaz)

      # Key too long (double size) - should fail
      long_key = :crypto.strong_rand_bytes(valid_pk_size * 2)
      assert {:error, _} = Crypto.kem_encapsulate(long_key, :kaz)

      # Note: Random garbage of correct size may "succeed" at the NIF level
      # (NIFs don't validate key structure, just size), but the result would
      # be unusable. This is expected behavior for many PQC implementations.

      # Test for NIST algorithm - wrong size should fail
      {:ok, nist_keypair} = Crypto.kem_keypair(:nist)
      nist_pk_size = byte_size(nist_keypair.public_key)

      short_nist_key = :crypto.strong_rand_bytes(div(nist_pk_size, 2))
      assert {:error, _} = Crypto.kem_encapsulate(short_nist_key, :nist)

      # Test for Hybrid algorithm - wrong size should fail
      {:ok, hybrid_keypair} = Crypto.kem_keypair(:hybrid)
      hybrid_pk_size = byte_size(hybrid_keypair.public_key)

      short_hybrid_key = :crypto.strong_rand_bytes(div(hybrid_pk_size, 2))
      assert {:error, _} = Crypto.kem_encapsulate(short_hybrid_key, :hybrid)
    end

    @tag :nif_behavior
    test "sign fails with truncated private key" do
      message = "test message to sign"

      # Get valid key sizes for reference
      {:ok, valid_keypair} = Crypto.sign_keypair(:kaz)
      valid_sk_size = byte_size(valid_keypair.private_key)

      # Truncated key (half size) - should fail
      truncated_key = binary_part(valid_keypair.private_key, 0, div(valid_sk_size, 2))
      assert {:error, _} = Crypto.sign(message, truncated_key, :kaz)

      # Note: Random garbage of correct size may "succeed" at the NIF level
      # (NIFs don't validate key structure, just size), producing an invalid
      # signature. This is expected behavior for many PQC implementations.

      # Test for NIST algorithm - truncated key should fail
      {:ok, nist_keypair} = Crypto.sign_keypair(:nist)
      nist_sk_size = byte_size(nist_keypair.private_key)

      truncated_nist_key = binary_part(nist_keypair.private_key, 0, div(nist_sk_size, 2))
      assert {:error, _} = Crypto.sign(message, truncated_nist_key, :nist)

      # Test for Hybrid algorithm - truncated key should fail
      {:ok, hybrid_keypair} = Crypto.sign_keypair(:hybrid)
      hybrid_sk_size = byte_size(hybrid_keypair.private_key)

      truncated_hybrid_key = binary_part(hybrid_keypair.private_key, 0, div(hybrid_sk_size, 2))
      assert {:error, _} = Crypto.sign(message, truncated_hybrid_key, :hybrid)
    end

    test "decrypt fails with wrong key size" do
      key = Crypto.generate_key()
      plaintext = "secret data"
      {:ok, ciphertext} = Crypto.encrypt(plaintext, key)

      # Try to decrypt with wrong size keys
      short_key = :crypto.strong_rand_bytes(16)
      assert {:error, _} = Crypto.decrypt(ciphertext, short_key)

      long_key = :crypto.strong_rand_bytes(64)
      assert {:error, _} = Crypto.decrypt(ciphertext, long_key)

      # Empty key
      assert {:error, _} = Crypto.decrypt(ciphertext, <<>>)
    end

    @tag :nif_behavior
    test "kem_decapsulate fails with truncated private key" do
      {:ok, keypair} = Crypto.kem_keypair(:kaz)
      {:ok, %{ciphertext: ct}} = Crypto.kem_encapsulate(keypair.public_key, :kaz)

      # Truncate private key
      sk_size = byte_size(keypair.private_key)
      truncated_sk = binary_part(keypair.private_key, 0, div(sk_size, 2))

      assert {:error, _} = Crypto.kem_decapsulate(ct, truncated_sk, :kaz)

      # Test with NIST
      {:ok, nist_keypair} = Crypto.kem_keypair(:nist)
      {:ok, %{ciphertext: nist_ct}} = Crypto.kem_encapsulate(nist_keypair.public_key, :nist)

      nist_sk_size = byte_size(nist_keypair.private_key)
      truncated_nist_sk = binary_part(nist_keypair.private_key, 0, div(nist_sk_size, 2))

      assert {:error, _} = Crypto.kem_decapsulate(nist_ct, truncated_nist_sk, :nist)
    end

    test "verify fails with truncated public key" do
      {:ok, keypair} = Crypto.sign_keypair(:kaz)
      message = "test message"
      {:ok, signature} = Crypto.sign(message, keypair.private_key, :kaz)

      # Truncate public key
      pk_size = byte_size(keypair.public_key)
      truncated_pk = binary_part(keypair.public_key, 0, div(pk_size, 2))

      assert {:error, _} = Crypto.verify(signature, truncated_pk, :kaz)

      # Test with NIST
      {:ok, nist_keypair} = Crypto.sign_keypair(:nist)
      {:ok, nist_sig} = Crypto.sign(message, nist_keypair.private_key, :nist)

      nist_pk_size = byte_size(nist_keypair.public_key)
      truncated_nist_pk = binary_part(nist_keypair.public_key, 0, div(nist_pk_size, 2))

      assert {:error, _} = Crypto.verify(nist_sig, truncated_nist_pk, :nist)
    end
  end

  describe "performance baselines" do
    @moduletag :benchmark

    @tag :benchmark
    test "KAZ-KEM encapsulate completes in < 10ms" do
      {:ok, keypair} = Crypto.kem_keypair(:kaz)

      # Warm up
      Crypto.kem_encapsulate(keypair.public_key, :kaz)

      # Measure average over 10 iterations
      times =
        for _ <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.kem_encapsulate(keypair.public_key, :kaz) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  KAZ-KEM encapsulate: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 10, "KAZ-KEM encapsulate avg #{avg_ms}ms exceeds 10ms threshold"
    end

    @tag :benchmark
    test "KAZ-KEM decapsulate completes in < 10ms" do
      {:ok, keypair} = Crypto.kem_keypair(:kaz)
      {:ok, %{ciphertext: ct}} = Crypto.kem_encapsulate(keypair.public_key, :kaz)

      # Warm up
      Crypto.kem_decapsulate(ct, keypair.private_key, :kaz)

      # Measure average over 10 iterations
      times =
        for _ <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.kem_decapsulate(ct, keypair.private_key, :kaz) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  KAZ-KEM decapsulate: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 10, "KAZ-KEM decapsulate avg #{avg_ms}ms exceeds 10ms threshold"
    end

    @tag :benchmark
    test "NIST ML-KEM encapsulate completes in < 5ms" do
      {:ok, keypair} = Crypto.kem_keypair(:nist)

      # Warm up
      Crypto.kem_encapsulate(keypair.public_key, :nist)

      # Measure average over 10 iterations
      times =
        for _ <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.kem_encapsulate(keypair.public_key, :nist) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  ML-KEM encapsulate: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 5, "ML-KEM encapsulate avg #{avg_ms}ms exceeds 5ms threshold"
    end

    @tag :benchmark
    test "KAZ-SIGN sign completes in < 10ms" do
      {:ok, keypair} = Crypto.sign_keypair(:kaz)
      message = "Test message for signing performance"

      # Warm up
      Crypto.sign(message, keypair.private_key, :kaz)

      # Measure average over 10 iterations
      times =
        for _ <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.sign(message, keypair.private_key, :kaz) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  KAZ-SIGN sign: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 10, "KAZ-SIGN sign avg #{avg_ms}ms exceeds 10ms threshold"
    end

    @tag :benchmark
    test "KAZ-SIGN verify completes in < 10ms" do
      {:ok, keypair} = Crypto.sign_keypair(:kaz)
      message = "Test message for signing performance"
      {:ok, signature} = Crypto.sign(message, keypair.private_key, :kaz)

      # Warm up
      Crypto.verify(signature, keypair.public_key, :kaz)

      # Measure average over 10 iterations
      times =
        for _ <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.verify(signature, keypair.public_key, :kaz) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  KAZ-SIGN verify: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 10, "KAZ-SIGN verify avg #{avg_ms}ms exceeds 10ms threshold"
    end

    @tag :benchmark
    test "Hybrid encryption of 1MB completes in < 100ms" do
      {:ok, keypair} = Crypto.kem_keypair(:hybrid)
      # 1MB of data
      plaintext = :crypto.strong_rand_bytes(1024 * 1024)

      # Warm up
      Crypto.hybrid_encrypt(plaintext, keypair.public_key, :hybrid)

      # Measure average over 5 iterations (fewer due to data size)
      times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} =
            :timer.tc(fn -> Crypto.hybrid_encrypt(plaintext, keypair.public_key, :hybrid) end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  Hybrid encrypt 1MB: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 100, "Hybrid encryption of 1MB avg #{avg_ms}ms exceeds 100ms threshold"
    end

    @tag :benchmark
    test "Hybrid decryption of 1MB completes in < 100ms" do
      {:ok, keypair} = Crypto.kem_keypair(:hybrid)
      plaintext = :crypto.strong_rand_bytes(1024 * 1024)
      {:ok, encrypted} = Crypto.hybrid_encrypt(plaintext, keypair.public_key, :hybrid)

      # Warm up
      Crypto.hybrid_decrypt(
        encrypted.ciphertext,
        encrypted.kem_ciphertext,
        keypair.private_key,
        :hybrid
      )

      # Measure average over 5 iterations
      times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} =
            :timer.tc(fn ->
              Crypto.hybrid_decrypt(
                encrypted.ciphertext,
                encrypted.kem_ciphertext,
                keypair.private_key,
                :hybrid
              )
            end)

          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  Hybrid decrypt 1MB: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 100, "Hybrid decryption of 1MB avg #{avg_ms}ms exceeds 100ms threshold"
    end

    @tag :benchmark
    test "AES-256-GCM encryption of 10MB completes in < 50ms" do
      key = Crypto.generate_key()
      # 10MB of data
      plaintext = :crypto.strong_rand_bytes(10 * 1024 * 1024)

      # Warm up
      Crypto.encrypt(plaintext, key)

      # Measure average over 5 iterations
      times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} = :timer.tc(fn -> Crypto.encrypt(plaintext, key) end)
          time_us
        end

      avg_ms = Enum.sum(times) / length(times) / 1000
      max_ms = Enum.max(times) / 1000

      IO.puts(
        "\n  AES-GCM encrypt 10MB: avg=#{Float.round(avg_ms, 2)}ms, max=#{Float.round(max_ms, 2)}ms"
      )

      assert avg_ms < 50, "AES-GCM encryption of 10MB avg #{avg_ms}ms exceeds 50ms threshold"
    end

    @tag :benchmark
    test "keypair generation performance" do
      # KAZ-KEM keypair
      kaz_kem_times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} = :timer.tc(fn -> Crypto.kem_keypair(:kaz) end)
          time_us
        end

      kaz_kem_avg = Enum.sum(kaz_kem_times) / length(kaz_kem_times) / 1000

      # NIST ML-KEM keypair
      nist_kem_times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} = :timer.tc(fn -> Crypto.kem_keypair(:nist) end)
          time_us
        end

      nist_kem_avg = Enum.sum(nist_kem_times) / length(nist_kem_times) / 1000

      # KAZ-SIGN keypair
      kaz_sign_times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} = :timer.tc(fn -> Crypto.sign_keypair(:kaz) end)
          time_us
        end

      kaz_sign_avg = Enum.sum(kaz_sign_times) / length(kaz_sign_times) / 1000

      # NIST ML-DSA keypair
      nist_sign_times =
        for _ <- 1..5 do
          {time_us, {:ok, _}} = :timer.tc(fn -> Crypto.sign_keypair(:nist) end)
          time_us
        end

      nist_sign_avg = Enum.sum(nist_sign_times) / length(nist_sign_times) / 1000

      IO.puts("\n  Keypair generation:")
      IO.puts("    KAZ-KEM: #{Float.round(kaz_kem_avg, 2)}ms")
      IO.puts("    ML-KEM: #{Float.round(nist_kem_avg, 2)}ms")
      IO.puts("    KAZ-SIGN: #{Float.round(kaz_sign_avg, 2)}ms")
      IO.puts("    ML-DSA: #{Float.round(nist_sign_avg, 2)}ms")

      # Generous thresholds for keypair generation
      assert kaz_kem_avg < 50, "KAZ-KEM keypair generation exceeds 50ms"
      assert nist_kem_avg < 10, "ML-KEM keypair generation exceeds 10ms"
      assert kaz_sign_avg < 50, "KAZ-SIGN keypair generation exceeds 50ms"
      assert nist_sign_avg < 50, "ML-DSA keypair generation exceeds 50ms"
    end
  end
end
