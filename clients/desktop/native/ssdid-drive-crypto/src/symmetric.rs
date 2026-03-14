//! Symmetric cryptographic operations
//!
//! Provides:
//! - AES-256-GCM encryption/decryption
//! - HKDF key derivation
//! - Argon2id password hashing
//! - Tiered KDF (argon2id-standard, argon2id-low, bcrypt-hkdf)

use crate::error::{CryptoError, CryptoResult};
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use argon2::Argon2;
use hkdf::Hkdf;
use sha2::{Sha256, Sha384};
use zeroize::{Zeroize, Zeroizing};

/// AES-256-GCM nonce size (96 bits)
pub const NONCE_SIZE: usize = 12;

/// AES-256-GCM tag size (128 bits)
pub const TAG_SIZE: usize = 16;

/// AES-256 key size
pub const KEY_SIZE: usize = 32;

/// Encrypt data using AES-256-GCM
///
/// Returns nonce || ciphertext || tag
pub fn encrypt_aes_gcm(plaintext: &[u8], key: &[u8]) -> CryptoResult<Vec<u8>> {
    if key.len() != KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: KEY_SIZE,
            actual: key.len(),
        });
    }

    let cipher = Aes256Gcm::new_from_slice(key)
        .map_err(|e| CryptoError::EncryptionFailed(e.to_string()))?;

    // Generate random nonce
    let mut nonce_bytes = [0u8; NONCE_SIZE];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| CryptoError::EncryptionFailed(e.to_string()))?;

    // Combine: nonce || ciphertext
    let mut result = Vec::with_capacity(NONCE_SIZE + ciphertext.len());
    result.extend_from_slice(&nonce_bytes);
    result.extend(ciphertext);

    Ok(result)
}

/// Decrypt data using AES-256-GCM
///
/// Expects nonce || ciphertext || tag
pub fn decrypt_aes_gcm(ciphertext: &[u8], key: &[u8]) -> CryptoResult<Zeroizing<Vec<u8>>> {
    if key.len() != KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: KEY_SIZE,
            actual: key.len(),
        });
    }

    if ciphertext.len() < NONCE_SIZE + TAG_SIZE {
        return Err(CryptoError::DecryptionFailed("Ciphertext too short".to_string()));
    }

    let cipher = Aes256Gcm::new_from_slice(key)
        .map_err(|e| CryptoError::DecryptionFailed(e.to_string()))?;

    let nonce = Nonce::from_slice(&ciphertext[..NONCE_SIZE]);
    let ciphertext_data = &ciphertext[NONCE_SIZE..];

    let plaintext = cipher
        .decrypt(nonce, ciphertext_data)
        .map_err(|e| CryptoError::DecryptionFailed(e.to_string()))?;

    Ok(Zeroizing::new(plaintext))
}

/// Derive a key using HKDF-SHA256
pub fn hkdf_derive(
    ikm: &[u8],
    salt: Option<&[u8]>,
    info: &[u8],
    output_len: usize,
) -> CryptoResult<Zeroizing<Vec<u8>>> {
    let hkdf = Hkdf::<Sha256>::new(salt, ikm);
    let mut output = vec![0u8; output_len];

    hkdf.expand(info, &mut output)
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;

    Ok(Zeroizing::new(output))
}

/// Argon2id parameters
pub struct Argon2Params {
    pub memory_cost: u32,
    pub time_cost: u32,
    pub parallelism: u32,
    pub output_len: usize,
}

impl Default for Argon2Params {
    fn default() -> Self {
        Self {
            memory_cost: 65536, // 64 MB
            time_cost: 3,
            parallelism: 4,
            output_len: 32,
        }
    }
}

/// Derive a key from password using Argon2id
pub fn argon2_derive(
    password: &[u8],
    salt: &[u8],
    params: &Argon2Params,
) -> CryptoResult<Zeroizing<Vec<u8>>> {
    let argon2 = Argon2::new(
        argon2::Algorithm::Argon2id,
        argon2::Version::V0x13,
        argon2::Params::new(
            params.memory_cost,
            params.time_cost,
            params.parallelism,
            Some(params.output_len),
        )
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?,
    );

    let mut output = vec![0u8; params.output_len];

    argon2
        .hash_password_into(password, salt, &mut output)
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;

    Ok(Zeroizing::new(output))
}

/// Generate a random salt
pub fn generate_salt(len: usize) -> Vec<u8> {
    let mut salt = vec![0u8; len];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut salt);
    salt
}

/// Generate a random key
pub fn generate_key() -> Zeroizing<Vec<u8>> {
    let mut key = vec![0u8; KEY_SIZE];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut key);
    Zeroizing::new(key)
}

// ==================== Tiered KDF ====================

/// Salt size for tiered KDF (16 bytes of random data)
pub const TIERED_KDF_SALT_SIZE: usize = 16;

/// Total wire salt size: 1 profile byte + 16 salt bytes
pub const TIERED_KDF_WIRE_SALT_SIZE: usize = 17;

/// KDF profile for tiered key derivation.
///
/// Wire format: `[profile_byte] || [salt_bytes (16 bytes)]`
/// Profile is selected based on device RAM to balance security and usability.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KdfProfile {
    /// argon2id-standard: 64 MiB, t=3, p=4 — Desktop and modern mobile (4+ GB RAM)
    Argon2idStandard,
    /// argon2id-low: 19 MiB, t=4, p=4 — Older mobile (2-4 GB RAM)
    Argon2idLow,
    /// bcrypt-hkdf: bcrypt cost=13 + HKDF-SHA-384 — Extremely constrained (< 2 GB RAM)
    BcryptHkdf,
}

impl KdfProfile {
    /// Profile byte for wire format
    pub fn profile_byte(&self) -> u8 {
        match self {
            KdfProfile::Argon2idStandard => 0x01,
            KdfProfile::Argon2idLow => 0x02,
            KdfProfile::BcryptHkdf => 0x03,
        }
    }

    /// Parse profile from wire byte
    pub fn from_byte(byte: u8) -> CryptoResult<Self> {
        match byte {
            0x01 => Ok(KdfProfile::Argon2idStandard),
            0x02 => Ok(KdfProfile::Argon2idLow),
            0x03 => Ok(KdfProfile::BcryptHkdf),
            _ => Err(CryptoError::KeyDerivationFailed(
                format!("Unknown KDF profile byte: 0x{:02x}", byte),
            )),
        }
    }

    /// Get Argon2 parameters for this profile (None for BcryptHkdf)
    pub fn argon2_params(&self) -> Option<Argon2Params> {
        match self {
            KdfProfile::Argon2idStandard => Some(Argon2Params {
                memory_cost: 65536,  // 64 MiB
                time_cost: 3,
                parallelism: 4,
                output_len: 32,
            }),
            KdfProfile::Argon2idLow => Some(Argon2Params {
                memory_cost: 19456,  // 19 MiB
                time_cost: 4,
                parallelism: 4,
                output_len: 32,
            }),
            KdfProfile::BcryptHkdf => None,
        }
    }
}

/// Bcrypt cost factor for bcrypt-hkdf profile
const BCRYPT_COST: u32 = 13;

/// HKDF salt for bcrypt-hkdf stretching
const BCRYPT_HKDF_SALT: &[u8] = b"SsdidDrive-Bcrypt-KDF-v1";

/// HKDF info for bcrypt-hkdf stretching
const BCRYPT_HKDF_INFO: &[u8] = b"bcrypt-derived-key";

/// Derive a key using bcrypt + HKDF-SHA-384.
///
/// 1. Bcrypt hash (cost=13) → 24-byte output
/// 2. HKDF-SHA-384 stretch to 32 bytes
pub fn bcrypt_hkdf_derive(password: &[u8], salt: &[u8]) -> CryptoResult<Zeroizing<Vec<u8>>> {
    // bcrypt requires exactly 16-byte salt
    if salt.len() != TIERED_KDF_SALT_SIZE {
        return Err(CryptoError::KeyDerivationFailed(
            format!("bcrypt requires 16-byte salt, got {}", salt.len()),
        ));
    }

    // bcrypt hash: produces 24 bytes
    let salt_array: [u8; 16] = salt.try_into().map_err(|_| {
        CryptoError::KeyDerivationFailed("invalid salt length for bcrypt".to_string())
    })?;
    let mut bcrypt_output = bcrypt::bcrypt(BCRYPT_COST, salt_array, password);

    // HKDF-SHA-384 stretch to 32 bytes
    let hkdf = Hkdf::<Sha384>::new(Some(BCRYPT_HKDF_SALT), &bcrypt_output);
    let mut output = vec![0u8; KEY_SIZE];

    hkdf.expand(BCRYPT_HKDF_INFO, &mut output)
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;

    // Zeroize intermediate bcrypt output
    bcrypt_output.zeroize();

    Ok(Zeroizing::new(output))
}

/// Create a salt with profile byte prepended.
///
/// Returns 17 bytes: `[profile_byte] || [16 random salt bytes]`
pub fn tiered_kdf_create_salt(profile: KdfProfile) -> Vec<u8> {
    let mut salt = Vec::with_capacity(TIERED_KDF_WIRE_SALT_SIZE);
    salt.push(profile.profile_byte());
    let random_salt = generate_salt(TIERED_KDF_SALT_SIZE);
    salt.extend_from_slice(&random_salt);
    salt
}

/// Derive a key using the tiered KDF system.
///
/// Parses the profile byte from the first byte of `salt_with_profile`,
/// then dispatches to the correct KDF based on profile.
///
/// For backward compatibility: if the salt is not 17 bytes or the first
/// byte is not a valid profile, falls back to legacy Argon2id-standard
/// with the raw salt.
pub fn tiered_kdf_derive(password: &[u8], salt_with_profile: &[u8]) -> CryptoResult<Zeroizing<Vec<u8>>> {
    // Check if this is a tiered salt (17 bytes, valid profile byte)
    if salt_with_profile.len() == TIERED_KDF_WIRE_SALT_SIZE {
        if let Ok(profile) = KdfProfile::from_byte(salt_with_profile[0]) {
            let salt = &salt_with_profile[1..];
            return match profile {
                KdfProfile::Argon2idStandard | KdfProfile::Argon2idLow => {
                    let params = profile.argon2_params().unwrap();
                    argon2_derive(password, salt, &params)
                }
                KdfProfile::BcryptHkdf => {
                    bcrypt_hkdf_derive(password, salt)
                }
            };
        }
    }

    // Legacy fallback: treat entire salt as Argon2id-standard salt
    let params = Argon2Params::default();
    argon2_derive(password, salt_with_profile, &params)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_aes_gcm_roundtrip() {
        let key = generate_key();
        let plaintext = b"Hello, SSDID Drive!";

        let ciphertext = encrypt_aes_gcm(plaintext, &key).unwrap();
        let decrypted = decrypt_aes_gcm(&ciphertext, &key).unwrap();

        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_hkdf() {
        let ikm = b"input key material";
        let salt = b"optional salt";
        let info = b"context info";

        let key1 = hkdf_derive(ikm, Some(salt), info, 32).unwrap();
        let key2 = hkdf_derive(ikm, Some(salt), info, 32).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), 32);
    }

    #[test]
    fn test_argon2() {
        let password = b"test password";
        let salt = generate_salt(32);
        let params = Argon2Params::default();

        let key1 = argon2_derive(password, &salt, &params).unwrap();
        let key2 = argon2_derive(password, &salt, &params).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), 32);
    }

    // ==================== Tiered KDF Tests ====================

    #[test]
    fn test_kdf_profile_byte_roundtrip() {
        for profile in [KdfProfile::Argon2idStandard, KdfProfile::Argon2idLow, KdfProfile::BcryptHkdf] {
            let byte = profile.profile_byte();
            let parsed = KdfProfile::from_byte(byte).unwrap();
            assert_eq!(profile, parsed);
        }
    }

    #[test]
    fn test_kdf_profile_from_invalid_byte() {
        assert!(KdfProfile::from_byte(0x00).is_err());
        assert!(KdfProfile::from_byte(0x04).is_err());
        assert!(KdfProfile::from_byte(0xFF).is_err());
    }

    #[test]
    fn test_kdf_profile_bytes() {
        assert_eq!(KdfProfile::Argon2idStandard.profile_byte(), 0x01);
        assert_eq!(KdfProfile::Argon2idLow.profile_byte(), 0x02);
        assert_eq!(KdfProfile::BcryptHkdf.profile_byte(), 0x03);
    }

    #[test]
    fn test_tiered_kdf_create_salt_format() {
        for profile in [KdfProfile::Argon2idStandard, KdfProfile::Argon2idLow, KdfProfile::BcryptHkdf] {
            let salt = tiered_kdf_create_salt(profile);
            assert_eq!(salt.len(), TIERED_KDF_WIRE_SALT_SIZE);
            assert_eq!(salt[0], profile.profile_byte());
        }
    }

    #[test]
    fn test_tiered_kdf_argon2id_standard_deterministic() {
        let password = b"correct horse battery staple";
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idStandard);

        let key1 = tiered_kdf_derive(password, &salt).unwrap();
        let key2 = tiered_kdf_derive(password, &salt).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), KEY_SIZE);
    }

    #[test]
    fn test_tiered_kdf_argon2id_low_deterministic() {
        let password = b"correct horse battery staple";
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idLow);

        let key1 = tiered_kdf_derive(password, &salt).unwrap();
        let key2 = tiered_kdf_derive(password, &salt).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), KEY_SIZE);
    }

    #[test]
    fn test_tiered_kdf_bcrypt_hkdf_deterministic() {
        let password = b"correct horse battery staple";
        let salt = tiered_kdf_create_salt(KdfProfile::BcryptHkdf);

        let key1 = tiered_kdf_derive(password, &salt).unwrap();
        let key2 = tiered_kdf_derive(password, &salt).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), KEY_SIZE);
    }

    #[test]
    fn test_tiered_kdf_different_profiles_different_keys() {
        let password = b"correct horse battery staple";
        let raw_salt = generate_salt(TIERED_KDF_SALT_SIZE);

        // Build salts with same random bytes but different profiles
        let mut salt_standard = vec![0x01];
        salt_standard.extend_from_slice(&raw_salt);

        let mut salt_low = vec![0x02];
        salt_low.extend_from_slice(&raw_salt);

        let mut salt_bcrypt = vec![0x03];
        salt_bcrypt.extend_from_slice(&raw_salt);

        let key_standard = tiered_kdf_derive(password, &salt_standard).unwrap();
        let key_low = tiered_kdf_derive(password, &salt_low).unwrap();
        let key_bcrypt = tiered_kdf_derive(password, &salt_bcrypt).unwrap();

        assert_ne!(key_standard, key_low);
        assert_ne!(key_standard, key_bcrypt);
        assert_ne!(key_low, key_bcrypt);
    }

    #[test]
    fn test_tiered_kdf_legacy_fallback() {
        let password = b"test password";
        // Legacy: 32-byte salt (no profile byte)
        let legacy_salt = generate_salt(32);

        let key_tiered = tiered_kdf_derive(password, &legacy_salt).unwrap();
        let key_direct = argon2_derive(password, &legacy_salt, &Argon2Params::default()).unwrap();

        assert_eq!(key_tiered, key_direct);
    }

    #[test]
    fn test_bcrypt_hkdf_derive_directly() {
        let password = b"test password";
        let salt = generate_salt(TIERED_KDF_SALT_SIZE);

        let key1 = bcrypt_hkdf_derive(password, &salt).unwrap();
        let key2 = bcrypt_hkdf_derive(password, &salt).unwrap();

        assert_eq!(key1, key2);
        assert_eq!(key1.len(), KEY_SIZE);
    }

    #[test]
    fn test_bcrypt_hkdf_derive_wrong_salt_size() {
        let password = b"test password";
        let salt = generate_salt(32); // Wrong size, should be 16

        assert!(bcrypt_hkdf_derive(password, &salt).is_err());
    }

    // ==================== Cross-Platform Test Vector Generation ====================

    /// Generate test vectors for all 3 KDF profiles using deterministic inputs.
    /// Run with: cargo test generate_test_vectors -- --nocapture
    #[test]
    fn generate_test_vectors() {
        let password = b"correct horse battery staple";
        let salt: [u8; 16] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                               0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10];

        println!("\n========== TIERED KDF TEST VECTORS ==========\n");

        // 5.2 argon2id-standard (profile 0x01)
        let params_standard = Argon2Params {
            memory_cost: 65536,
            time_cost: 3,
            parallelism: 4,
            output_len: 32,
        };
        let key_standard = argon2_derive(password, &salt, &params_standard).unwrap();
        println!("5.2 argon2id-standard:");
        println!("  password (hex): {}", hex::encode(password));
        println!("  salt (hex):     {}", hex::encode(&salt));
        println!("  derived_key:    {}", hex::encode(&key_standard));
        println!("  wire_salt:      01{}", hex::encode(&salt));
        println!();

        // 5.3 argon2id-low (profile 0x02)
        let params_low = Argon2Params {
            memory_cost: 19456,
            time_cost: 4,
            parallelism: 4,
            output_len: 32,
        };
        let key_low = argon2_derive(password, &salt, &params_low).unwrap();
        println!("5.3 argon2id-low:");
        println!("  password (hex): {}", hex::encode(password));
        println!("  salt (hex):     {}", hex::encode(&salt));
        println!("  derived_key:    {}", hex::encode(&key_low));
        println!("  wire_salt:      02{}", hex::encode(&salt));
        println!();

        // 5.4 bcrypt-hkdf (profile 0x03)
        // Step 1: bcrypt raw output (24 bytes)
        let bcrypt_raw = bcrypt::bcrypt(BCRYPT_COST, salt, password);
        println!("5.4 bcrypt-hkdf:");
        println!("  password (hex): {}", hex::encode(password));
        println!("  salt (hex):     {}", hex::encode(&salt));
        println!("  bcrypt_output (24 bytes): {}", hex::encode(&bcrypt_raw));

        // Step 2: HKDF-SHA-384 stretch
        let key_bcrypt = bcrypt_hkdf_derive(password, &salt).unwrap();
        println!("  derived_key:    {}", hex::encode(&key_bcrypt));
        println!("  wire_salt:      03{}", hex::encode(&salt));
        println!();

        // Verify via tiered_kdf_derive roundtrip
        let mut wire_standard = vec![0x01];
        wire_standard.extend_from_slice(&salt);
        let verify_standard = tiered_kdf_derive(password, &wire_standard).unwrap();
        assert_eq!(key_standard, verify_standard);

        let mut wire_low = vec![0x02];
        wire_low.extend_from_slice(&salt);
        let verify_low = tiered_kdf_derive(password, &wire_low).unwrap();
        assert_eq!(key_low, verify_low);

        let mut wire_bcrypt = vec![0x03];
        wire_bcrypt.extend_from_slice(&salt);
        let verify_bcrypt = tiered_kdf_derive(password, &wire_bcrypt).unwrap();
        assert_eq!(key_bcrypt, verify_bcrypt);

        println!("All tiered_kdf_derive roundtrips verified!");
    }

    /// Verify argon2id-standard against published test vector (section 5.2)
    #[test]
    fn test_vector_argon2id_standard() {
        let password = b"correct horse battery staple";
        let salt = hex::decode("0102030405060708090a0b0c0d0e0f10").unwrap();
        let wire_salt = hex::decode("010102030405060708090a0b0c0d0e0f10").unwrap();

        let key = tiered_kdf_derive(password, &wire_salt).unwrap();

        assert_eq!(
            hex::encode(&key),
            "6ec690471257037ee9c75b275e6161c1c2f4335ab541400534dba6769a444397"
        );

        // Also verify direct argon2 call matches
        let params = KdfProfile::Argon2idStandard.argon2_params().unwrap();
        let key_direct = argon2_derive(password, &salt, &params).unwrap();
        assert_eq!(key, key_direct);
    }

    /// Verify argon2id-low against published test vector (section 5.3)
    #[test]
    fn test_vector_argon2id_low() {
        let password = b"correct horse battery staple";
        let salt = hex::decode("0102030405060708090a0b0c0d0e0f10").unwrap();
        let wire_salt = hex::decode("020102030405060708090a0b0c0d0e0f10").unwrap();

        let key = tiered_kdf_derive(password, &wire_salt).unwrap();

        assert_eq!(
            hex::encode(&key),
            "1025994eae82eff51c942eed6294d085a1d43526998ed20e22c1f63e1c592a88"
        );

        // Also verify direct argon2 call matches
        let params = KdfProfile::Argon2idLow.argon2_params().unwrap();
        let key_direct = argon2_derive(password, &salt, &params).unwrap();
        assert_eq!(key, key_direct);
    }

    /// Verify bcrypt-hkdf against published test vector (section 5.4)
    #[test]
    fn test_vector_bcrypt_hkdf() {
        let password = b"correct horse battery staple";
        let salt = hex::decode("0102030405060708090a0b0c0d0e0f10").unwrap();
        let wire_salt = hex::decode("030102030405060708090a0b0c0d0e0f10").unwrap();

        // Verify intermediate bcrypt output
        let salt_array: [u8; 16] = salt.clone().try_into().unwrap();
        let bcrypt_output = bcrypt::bcrypt(BCRYPT_COST, salt_array, password);
        assert_eq!(
            hex::encode(&bcrypt_output),
            "b0bd8f45c23e9c8e41705c842a997336cd987356fbf235e2"
        );

        // Verify final derived key via tiered dispatch
        let key = tiered_kdf_derive(password, &wire_salt).unwrap();
        assert_eq!(
            hex::encode(&key),
            "9ac8238c6d6cfb684b65d74a09bc374c89fda665557ff1cc5413feeb54ce33b7"
        );

        // Verify direct call matches
        let key_direct = bcrypt_hkdf_derive(password, &salt).unwrap();
        assert_eq!(key, key_direct);
    }
}
