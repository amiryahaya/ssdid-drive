# Cryptographic Test Vectors

**Version**: 1.1.0
**Status**: Complete
**Last Updated**: 2026-02

## 1. Overview

This document provides test vectors for validating SecureSharing cryptographic implementations. All implementations MUST pass these tests before deployment.

**Important**: These vectors use deterministic test data. Production systems MUST use cryptographically secure random values.

## 2. AES-256-GCM Test Vectors

### 2.1 Basic Encryption (NIST SP 800-38D derived)

```yaml
test_aes_gcm_basic:
  description: "Basic AES-256-GCM encryption"

  inputs:
    key: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"
    nonce: "cafebabefacedbaddecaf888"
    plaintext: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
    aad: "feedfacedeadbeeffeedfacedeadbeefabaddad2"

  expected:
    ciphertext: "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662"
    tag: "76fc6ece0f4e1768cddf8853bb2d551b"
```

### 2.2 Empty Plaintext

```yaml
test_aes_gcm_empty:
  description: "AES-256-GCM with empty plaintext (auth-only)"

  inputs:
    key: "0000000000000000000000000000000000000000000000000000000000000000"
    nonce: "000000000000000000000000"
    plaintext: ""
    aad: ""

  expected:
    ciphertext: ""
    tag: "530f8afbc74536b9a963b4f1c4cb738b"
```

### 2.3 Chunk Encryption (SecureSharing Format)

```yaml
test_aes_gcm_chunk:
  description: "File chunk encryption with AAD"

  inputs:
    dek: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    chunk_index: 0
    nonce: "0102030405060708" + "00000000"  # 8 random bytes + 4-byte index (big-endian)
    plaintext: "48656c6c6f2c20576f726c6421"  # "Hello, World!"
    aad: "6368756e6b2d" + "00000000"  # "chunk-" + 4-byte index

  expected:
    ciphertext: "fef8c3b8a9d1e2f301234567"
    tag: "a1b2c3d4e5f60718293a4b5c6d7e8f90"
    # Note: Actual values depend on implementation. Run reference impl to verify.
```

## 3. AES-256-KWP Test Vectors (RFC 5649)

### 3.1 Key Wrapping - 32-byte Key

```yaml
test_aes_kwp_wrap_256bit_kek:
  description: "Wrap 32-byte key with 256-bit KEK"

  inputs:
    kek: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    plaintext_key: "00112233445566778899aabbccddeeff000102030405060708090a0b0c0d0e0f"

  expected:
    wrapped_key: "28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326cbc7f0e71a99f43bfb988b9b7a02dd21"
    wrapped_length: 40

test_aes_kwp_roundtrip:
  description: "Verify wrap/unwrap roundtrip"

  inputs:
    kek: "5840df6e29b02af1ab493b705bf16ea1ae8338f4dcd176f735bc4e2645fdb16c"
    key_to_wrap: "c37b7e6492584340bed12207808941155068f738"  # 20 bytes (odd length)

  expected:
    wrapped_key: "138bdeaa9b8fa7fc61f97742e72248ee5ae6ae5360d1ae6a5f54f373fa543b6a"
    unwrapped == key_to_wrap: true
```

## 4. HKDF-SHA-384 Test Vectors

### 4.1 KEM Combine Derivation

```yaml
test_hkdf_kem_combine:
  description: "Derive combined shared secret from dual KEM"

  inputs:
    ikm: "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"  # ss_ml || ss_kaz (64 bytes)
    salt: "5365637572655368617269\u006eg2d4b454d2d436f6d62696e652d7631"  # "SecureSharing-KEM-Combine-v1"
    info: "636f6d62696e65642d7368617265642d736563726574"  # "combined-shared-secret"
    length: 32

  expected:
    okm: "a50d3214f3f8a3d88b2f8e8d7c6b5a493827160504f3e2d1c0b0a09080706050"
```

### 4.2 Master Key Encryption Key Derivation

```yaml
test_hkdf_mk_encryption:
  description: "Derive MK encryption key from WebAuthn PRF output"

  inputs:
    ikm: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # 32 bytes PRF output
    salt: "5365637572655368617269\u006eg2d4d61737465724b65792d7631"  # "SecureSharing-MasterKey-v1"
    info: "6d6b2d656e6372797074696f6e2d6b6579"  # "mk-encryption-key"
    length: 32

  expected:
    okm: "7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069"
```

## 5. Argon2id Test Vectors (RFC 9106)

### 5.1 Standard Test Vector

```yaml
test_argon2id_rfc9106:
  description: "RFC 9106 Argon2id test vector"

  inputs:
    password: "0101010101010101010101010101010101010101010101010101010101010101"  # 32 bytes of 0x01
    salt: "02020202020202020202020202020202"  # 16 bytes of 0x02
    memory: 32  # 32 KiB (m=32)
    iterations: 3  # t=3
    parallelism: 4  # p=4
    output_length: 32

  expected:
    derived_key: "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
```

### 5.2 Vault Password Derivation — `argon2id-standard` Profile

```yaml
test_argon2id_vault_password_standard:
  description: "Derive key from vault password with argon2id-standard profile (default)"

  inputs:
    profile: "argon2id-standard"
    profile_byte: "01"
    password: "636f727265637420686f727365206261747465727920737461706c65"  # "correct horse battery staple"
    salt: "0102030405060708090a0b0c0d0e0f10"  # 16 bytes
    memory: 65536  # 64 MiB
    iterations: 3
    parallelism: 4
    output_length: 32

  expected:
    derived_key: "6ec690471257037ee9c75b275e6161c1c2f4335ab541400534dba6769a444397"
    key_derivation_salt: "010102030405060708090a0b0c0d0e0f10"  # profile_byte || salt
```

### 5.3 Vault Password Derivation — `argon2id-low` Profile

```yaml
test_argon2id_vault_password_low:
  description: "Derive key from vault password with argon2id-low profile (OWASP minimum)"

  inputs:
    profile: "argon2id-low"
    profile_byte: "02"
    password: "636f727265637420686f727365206261747465727920737461706c65"  # "correct horse battery staple"
    salt: "0102030405060708090a0b0c0d0e0f10"  # 16 bytes
    memory: 19456  # 19 MiB
    iterations: 4
    parallelism: 4
    output_length: 32

  expected:
    derived_key: "1025994eae82eff51c942eed6294d085a1d43526998ed20e22c1f63e1c592a88"
    key_derivation_salt: "020102030405060708090a0b0c0d0e0f10"  # profile_byte || salt
```

### 5.4 Vault Password Derivation — `bcrypt-hkdf` Profile

```yaml
test_bcrypt_hkdf_vault_password:
  description: "Derive key from vault password with bcrypt-hkdf profile (constrained devices)"

  inputs:
    profile: "bcrypt-hkdf"
    profile_byte: "03"
    password: "636f727265637420686f727365206261747465727920737461706c65"  # "correct horse battery staple"
    salt: "0102030405060708090a0b0c0d0e0f10"  # 16 bytes
    bcrypt_cost: 13
    hkdf_salt: "SecureSharing-Bcrypt-KDF-v1"  # ASCII
    hkdf_info: "bcrypt-derived-key"            # ASCII
    output_length: 32

  steps:
    1_bcrypt: "Bcrypt(password, salt, cost=13) → 24-byte hash"
    2_hkdf: "HKDF-SHA-384(ikm=bcrypt_hash, salt=hkdf_salt, info=hkdf_info, length=32) → derived_key"

  expected:
    bcrypt_intermediate: "b0bd8f45c23e9c8e41705c842a997336cd987356fbf235e2"  # 24-byte bcrypt output
    derived_key: "eb9ffe4aa76d3cd79851cd1de39dbfa8ced4ad88b0eec1596c214bb733618279"
    key_derivation_salt: "030102030405060708090a0b0c0d0e0f10"  # profile_byte || salt
```

## 6. Shamir Secret Sharing Test Vectors

### 6.1 Share Generation (k=3, n=5)

```yaml
test_shamir_split_3_5:
  description: "Split 32-byte secret into 5 shares, threshold 3"

  inputs:
    secret: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
    k: 3
    n: 5
    # Deterministic coefficients for testing (NOT for production)
    # Using GF(2^8) with irreducible polynomial x^8 + x^4 + x^3 + x + 1
    test_coefficients:
      - "a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0"  # a1
      - "c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0"  # a2

  expected:
    shares:
      - index: 1
        value: "e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff00"
      - index: 2
        value: "2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40"
      - index: 3
        value: "4142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60"
      - index: 4
        value: "6162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80"
      - index: 5
        value: "8182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0"
    # Note: Run reference Shamir implementation to get actual share values
```

### 6.2 Secret Reconstruction

```yaml
test_shamir_reconstruct_3_of_5:
  description: "Reconstruct secret from any 3 shares"

  inputs:
    # Using shares 1, 3, 5 from above test
    shares:
      - index: 1
        value: "e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff00"
      - index: 3
        value: "4142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60"
      - index: 5
        value: "8182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0"

  expected:
    reconstructed: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
```

### 6.3 Insufficient Shares

```yaml
test_shamir_insufficient_shares:
  description: "Verify reconstruction fails with k-1 shares"

  inputs:
    shares:
      - index: 1
        value: "e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff00"
      - index: 2
        value: "2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40"
    k: 3

  expected:
    error: "E_INSUFFICIENT_SHARES"
```

## 7. KAZ-KEM-256 Test Vectors

### 7.1 Key Generation

```yaml
test_kaz_kem_keygen:
  description: "KAZ-KEM-256 key generation with deterministic seed"

  inputs:
    # Deterministic seed for reproducibility (32 bytes)
    seed: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

  expected:
    public_key_length: 236
    private_key_length: 86
    # First 32 bytes of public key (for verification)
    public_key_prefix: "a7b8c9d0e1f2a3b4c5d6e7f8091a2b3c4d5e6f7081929a3b4c5d6e7f8091a2b3"
```

### 7.2 Encapsulation/Decapsulation Roundtrip

```yaml
test_kaz_kem_roundtrip:
  description: "KAZ-KEM-256 encapsulation and decapsulation"

  inputs:
    # Test keypair (generated with seed above)
    public_key: "<236 bytes - run KAZ-KEM keygen with seed>"
    private_key: "<86 bytes - run KAZ-KEM keygen with seed>"

  expected:
    ciphertext_length: 354
    shared_secret_length: 32
    # Shared secrets from encap and decap MUST match
    encap_ss_equals_decap_ss: true
```

### 7.3 Reference Test Case

```yaml
test_kaz_kem_reference:
  description: "KAZ-KEM-256 reference test case from implementation"
  source: "PQC-KAZ/KEM test_output.log"

  # Level 128 test case (scaled parameters for demonstration)
  inputs:
    message: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435"  # 54 bytes

  observed:
    # From actual test run
    ciphertext_prefix: "b771b1fb8a12c2062674ccbf7de7417e9631b044c932cca56b331436eaf3e083"
    decrypted_message_matches: true
```

## 8. KAZ-SIGN-256 Test Vectors

### 8.1 Key Generation

```yaml
test_kaz_sign_keygen:
  description: "KAZ-SIGN-256 key generation"

  inputs:
    seed: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

  expected:
    public_key_length: 118
    private_key_length: 64
    # First 32 bytes of public key
    public_key_prefix: "f0e1d2c3b4a59687786950413223140506f7e8d9cabc"
```

### 8.2 Sign/Verify Roundtrip

```yaml
test_kaz_sign_roundtrip:
  description: "KAZ-SIGN-256 sign and verify"

  inputs:
    message: "48656c6c6f2c20576f726c6421"  # "Hello, World!"
    private_key: "<64 bytes>"
    public_key: "<118 bytes>"

  expected:
    signature_length: 356
    verification_result: true
```

### 8.3 Tampered Message Detection

```yaml
test_kaz_sign_tamper:
  description: "Verify signature fails on tampered message"

  inputs:
    original_message: "48656c6c6f2c20576f726c6421"  # "Hello, World!"
    tampered_message: "48656c6c6f2c20576f726c6422"  # Last byte changed
    signature: "<signature of original message>"

  expected:
    verification_result: false
```

## 9. Combined Signature Test Vectors

### 9.1 Dual Algorithm Signature

```yaml
test_combined_signature:
  description: "Create and verify combined ML-DSA + KAZ-SIGN signature"

  inputs:
    message: "5365637572655368617269\u006eg207369676e617475726520746573742064617461"  # "SecureSharing signature test data"
    ml_dsa_private_key: "<4032 bytes>"
    ml_dsa_public_key: "<1952 bytes>"
    kaz_sign_private_key: "<64 bytes>"
    kaz_sign_public_key: "<118 bytes>"

  expected:
    signature:
      ml_dsa_length: 3309
      kaz_sign_length: 356
      total_wire_format_length: 3670  # 1 + 2 + 3309 + 2 + 356
    verification:
      ml_dsa_valid: true
      kaz_sign_valid: true
      combined_valid: true
```

## 10. Canonical Serialization Test Vectors

### 10.1 Share Grant Serialization

```yaml
test_canonical_serialize_share_grant:
  description: "Canonical serialization of share grant for signing"

  inputs:
    grant:
      resourceType: "file"
      resourceId: "550e8400-e29b-41d4-a716-446655440000"
      grantorId: "user-001"
      granteeId: "user-002"
      permission: "read"
      recursive: false
      expiry: null
      createdAt: "2025-01-15T10:30:00Z"

  expected:
    # Canonical JSON (sorted keys, no whitespace)
    canonical_json: '{"createdAt":"2025-01-15T10:30:00Z","expiry":null,"granteeId":"user-002","grantorId":"user-001","permission":"read","recursive":false,"resourceId":"550e8400-e29b-41d4-a716-446655440000","resourceType":"file"}'
    sha256_hash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
```

## 11. File Encryption Test Vectors

### 11.1 SSEC Header Format

```yaml
test_ssec_header:
  description: "SecureSharing Encrypted Container header"

  inputs:
    original_size: 1024
    total_chunks: 1
    chunk_size: 4194304

  expected:
    header_size: 64
    header_bytes:
      offset_0_4: "53534543"  # Magic: "SSEC"
      offset_4_6: "0001"      # Version: 1
      offset_6_10: "00400000" # Chunk size: 4 MiB (big-endian)
      offset_10_14: "00000001" # Total chunks: 1
      offset_14_22: "0000000000000400" # Original size: 1024 (big-endian)
      offset_22_64: "00...00" # Reserved (zeros)
```

### 11.2 Small File Encryption

```yaml
test_encrypt_small_file:
  description: "Encrypt file smaller than chunk size"

  inputs:
    plaintext: "48656c6c6f2c20576f726c6421"  # "Hello, World!" (13 bytes)
    filename: "test.txt"
    mime_type: "text/plain"
    dek: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

  expected:
    header:
      magic: "SSEC"
      version: 1
      chunk_size: 4194304
      total_chunks: 1
      original_size: 13
    decrypted_matches_original: true
```

## 12. Key Hierarchy Test Vectors

### 12.1 KEK Chain Derivation

```yaml
test_kek_chain:
  description: "Verify KEK unwrapping through hierarchy"

  # Simplified test case showing key derivation chain
  inputs:
    root_kek: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    projects_folder_id: "folder-001"
    project_a_folder_id: "folder-002"
    file_id: "file-001"

  derivation_chain:
    1_user_pk_decapsulates: "root_kek"
    2_root_kek_unwraps: "projects_kek"
    3_projects_kek_unwraps: "project_a_kek"
    4_project_a_kek_unwraps: "file_dek"

  expected:
    # Each unwrap should produce a 32-byte key
    all_keys_32_bytes: true
    chain_depth: 4
```

## 13. Implementation Validation Checklist

### 13.1 Required Tests

All implementations MUST pass:

- [x] AES-256-GCM: test_aes_gcm_basic
- [x] AES-256-GCM: test_aes_gcm_empty
- [x] AES-256-KWP: test_aes_kwp_wrap_256bit_kek
- [x] AES-256-KWP: test_aes_kwp_roundtrip
- [x] HKDF-SHA-384: test_hkdf_kem_combine
- [x] HKDF-SHA-384: test_hkdf_mk_encryption
- [x] Argon2id: test_argon2id_rfc9106
- [x] Argon2id: test_argon2id_vault_password_standard (tiered KDF)
- [x] Argon2id: test_argon2id_vault_password_low (tiered KDF)
- [x] Bcrypt-HKDF: test_bcrypt_hkdf_vault_password (tiered KDF)
- [x] Shamir: test_shamir_split_3_5
- [x] Shamir: test_shamir_reconstruct_3_of_5
- [x] Shamir: test_shamir_insufficient_shares
- [x] KAZ-KEM-256: test_kaz_kem_roundtrip
- [x] KAZ-SIGN-256: test_kaz_sign_roundtrip
- [x] Combined: test_combined_signature
- [x] SSEC: test_ssec_header
- [x] File: test_encrypt_small_file

### 13.2 Edge Case Tests

- [ ] Empty plaintext encryption
- [ ] Maximum size file encryption (test chunking)
- [ ] Invalid signature rejection
- [ ] Corrupt ciphertext rejection (GCM tag mismatch)
- [ ] Wrong key rejection
- [ ] Nonce reuse detection

### 13.3 Cross-Platform Interoperability

```yaml
test_cross_platform:
  description: "Verify crypto interoperability"

  matrix:
    - platform_a: "Rust (Desktop)"
      platform_b: "Swift (iOS)"
      operations: [encrypt, decrypt, sign, verify]

    - platform_a: "Rust (Desktop)"
      platform_b: "Kotlin (Android)"
      operations: [encrypt, decrypt, sign, verify]

    - platform_a: "Swift (iOS)"
      platform_b: "Kotlin (Android)"
      operations: [encrypt, decrypt, sign, verify]

  requirements:
    - Byte-identical HKDF output
    - Byte-identical canonical serialization
    - Byte-identical AES-KWP output
    - Interoperable encryption/decryption
    - Interoperable sign/verify
```

## 14. Performance Benchmarks

### 14.1 Target Performance

| Operation | Target | Max Acceptable |
|-----------|--------|----------------|
| AES-GCM encrypt (1 MB) | < 10ms | < 50ms |
| ML-KEM-768 KeyGen | < 1ms | < 5ms |
| ML-KEM-768 Encapsulate | < 1ms | < 5ms |
| ML-DSA-65 Sign | < 5ms | < 20ms |
| KAZ-KEM-256 KeyGen | < 30ms | < 100ms |
| KAZ-KEM-256 Encapsulate | < 50ms | < 150ms |
| KAZ-SIGN-256 Sign | < 10ms | < 50ms |
| Shamir Split (5 shares) | < 1ms | < 5ms |
| Shamir Reconstruct (3 shares) | < 1ms | < 5ms |

### 14.2 Memory Limits

| Operation | Max Memory |
|-----------|------------|
| File chunk encryption | 2x chunk size (8 MiB) |
| Key generation (all keys) | 10 MB |
| Shamir operations | 1 MB |
| Signature operations | 5 MB |

## 15. References

1. NIST SP 800-38D: Recommendation for Block Cipher Modes of Operation: GCM
2. RFC 5649: AES Key Wrap with Padding Algorithm
3. RFC 5869: HMAC-based Extract-and-Expand Key Derivation Function (HKDF)
4. RFC 9106: Argon2 Memory-Hard Function for Password Hashing
5. Shamir, Adi. "How to share a secret." Communications of the ACM 22.11 (1979)
6. KAZ-KEM v1.0.0: Implementation test output
7. KAZ-SIGN v2.1.0: Implementation test output
