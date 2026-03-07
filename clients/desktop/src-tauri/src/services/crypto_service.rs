//! Cryptographic operations service

use crate::commands::crypto::{EncryptionResult, SignatureResult};
use crate::error::{AppError, AppResult};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use parking_lot::RwLock;
use ssdid_drive_crypto::{
    kaz_kem, kaz_sign, ml_dsa, ml_kem,
    symmetric::{
        argon2_derive, decrypt_aes_gcm, encrypt_aes_gcm, generate_key, generate_salt, hkdf_derive,
        tiered_kdf_create_salt, tiered_kdf_derive, Argon2Params, KdfProfile, KEY_SIZE,
    },
};
use zeroize::Zeroize;

/// Service for cryptographic operations
pub struct CryptoService {
    initialized: bool,
    /// Current master key (in memory, zeroized on drop)
    master_key: RwLock<Option<Vec<u8>>>,
}

impl CryptoService {
    /// Create a new crypto service
    pub fn new() -> AppResult<Self> {
        // Initialize the crypto library
        ssdid_drive_crypto::init()
            .map_err(|e| AppError::Crypto(format!("Failed to initialize crypto: {}", e)))?;

        Ok(Self {
            initialized: true,
            master_key: RwLock::new(None),
        })
    }

    /// Check if crypto is initialized
    pub fn is_initialized(&self) -> bool {
        self.initialized
    }

    /// Set the decrypted master key in memory
    pub fn set_master_key(&self, key: Vec<u8>) -> AppResult<()> {
        if key.len() != KEY_SIZE {
            return Err(AppError::Crypto("Invalid master key size".to_string()));
        }
        *self.master_key.write() = Some(key);
        Ok(())
    }

    /// Clear the master key from memory
    pub fn clear_master_key(&self) {
        if let Some(mut key) = self.master_key.write().take() {
            key.zeroize();
        }
    }

    /// Check if master key is loaded
    pub fn has_master_key(&self) -> bool {
        self.master_key.read().is_some()
    }

    /// Get a clone of the master key (for recovery setup)
    /// This is a security-sensitive operation - use carefully
    pub fn get_master_key(&self) -> AppResult<Vec<u8>> {
        self.master_key
            .read()
            .clone()
            .ok_or_else(|| AppError::Crypto("Master key not loaded".to_string()))
    }

    // ==================== Key Generation ====================

    /// Generate ML-KEM-768 key pair
    pub fn generate_ml_kem_keypair(&self) -> AppResult<(String, String)> {
        let keypair = ml_kem::generate_keypair()
            .map_err(|e| AppError::Crypto(format!("ML-KEM keygen failed: {}", e)))?;

        Ok((
            BASE64.encode(&keypair.public_key),
            BASE64.encode(&keypair.secret_key),
        ))
    }

    /// Generate ML-DSA-65 key pair
    pub fn generate_ml_dsa_keypair(&self) -> AppResult<(String, String)> {
        let keypair = ml_dsa::generate_keypair()
            .map_err(|e| AppError::Crypto(format!("ML-DSA keygen failed: {}", e)))?;

        Ok((
            BASE64.encode(&keypair.public_key),
            BASE64.encode(&keypair.secret_key),
        ))
    }

    /// Generate KAZ-KEM-256 key pair
    pub fn generate_kaz_kem_keypair(&self) -> AppResult<(String, String)> {
        let keypair = kaz_kem::generate_keypair()
            .map_err(|e| AppError::Crypto(format!("KAZ-KEM keygen failed: {}", e)))?;

        Ok((
            BASE64.encode(&keypair.public_key),
            BASE64.encode(keypair.secret_key()),
        ))
    }

    /// Generate KAZ-SIGN-256 key pair
    pub fn generate_kaz_sign_keypair(&self) -> AppResult<(String, String)> {
        let keypair = kaz_sign::generate_keypair(kaz_sign::SecurityLevel::Level256)
            .map_err(|e| AppError::Crypto(format!("KAZ-SIGN keygen failed: {}", e)))?;

        Ok((
            BASE64.encode(&keypair.public_key),
            BASE64.encode(keypair.secret_key()),
        ))
    }

    /// Generate a random master key (32 bytes)
    pub fn generate_master_key(&self) -> AppResult<Vec<u8>> {
        Ok(generate_key())
    }

    /// Generate a Data Encryption Key (DEK)
    pub fn generate_dek(&self) -> AppResult<Vec<u8>> {
        Ok(generate_key())
    }

    // ==================== Key Derivation ====================

    /// Derive authentication key from password using tiered KDF.
    /// Desktop always uses Argon2idStandard for new salts.
    pub fn derive_auth_key(&self, password: &str) -> AppResult<(String, String)> {
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idStandard);

        let key = tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))?;

        Ok((BASE64.encode(&salt), BASE64.encode(&key)))
    }

    /// Derive encryption key from password and existing salt.
    /// Automatically detects tiered vs legacy salt format.
    pub fn derive_encryption_key(&self, password: &str, salt_b64: &str) -> AppResult<Vec<u8>> {
        let salt = BASE64
            .decode(salt_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid salt: {}", e)))?;

        tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))
    }

    /// Derive encryption key with new salt using tiered KDF.
    /// Desktop always uses Argon2idStandard for new salts.
    pub fn derive_encryption_key_with_salt(&self, password: &str) -> AppResult<(String, Vec<u8>)> {
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idStandard);

        let key = tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))?;

        Ok((BASE64.encode(&salt), key))
    }

    /// Derive a folder Key Encryption Key (KEK) from master key
    pub fn derive_folder_kek(&self, folder_id: &str) -> AppResult<Vec<u8>> {
        let master_key = self.master_key.read();
        let master_key = master_key
            .as_ref()
            .ok_or_else(|| AppError::Crypto("Master key not loaded".to_string()))?;

        let info = format!("folder-kek:{}", folder_id);
        hkdf_derive(master_key, None, info.as_bytes(), KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("KEK derivation failed: {}", e)))
    }

    // ==================== Encryption/Decryption ====================

    /// Encrypt master key with derived encryption key
    pub fn encrypt_master_key(
        &self,
        master_key: &[u8],
        enc_key: &[u8],
    ) -> AppResult<(String, String)> {
        let ciphertext = encrypt_aes_gcm(master_key, enc_key)
            .map_err(|e| AppError::Crypto(format!("Master key encryption failed: {}", e)))?;

        // Split nonce and ciphertext (nonce is first 12 bytes)
        let nonce = &ciphertext[..12];
        let ct = &ciphertext[12..];

        Ok((BASE64.encode(ct), BASE64.encode(nonce)))
    }

    /// Decrypt master key with derived encryption key
    pub fn decrypt_master_key(
        &self,
        encrypted_mk_b64: &str,
        nonce_b64: &str,
        enc_key: &[u8],
    ) -> AppResult<Vec<u8>> {
        let encrypted_mk = BASE64
            .decode(encrypted_mk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ciphertext: {}", e)))?;
        let nonce = BASE64
            .decode(nonce_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid nonce: {}", e)))?;

        // Reconstruct the full ciphertext (nonce || ciphertext)
        let mut full_ciphertext = Vec::with_capacity(nonce.len() + encrypted_mk.len());
        full_ciphertext.extend_from_slice(&nonce);
        full_ciphertext.extend_from_slice(&encrypted_mk);

        decrypt_aes_gcm(&full_ciphertext, enc_key)
            .map_err(|e| AppError::Crypto(format!("Master key decryption failed: {}", e)))
    }

    /// Encrypt a private key with master key
    pub fn encrypt_private_key(&self, private_key: &str, master_key: &[u8]) -> AppResult<String> {
        let pk_bytes = BASE64
            .decode(private_key)
            .map_err(|e| AppError::Crypto(format!("Invalid private key: {}", e)))?;

        let ciphertext = encrypt_aes_gcm(&pk_bytes, master_key)
            .map_err(|e| AppError::Crypto(format!("Private key encryption failed: {}", e)))?;

        Ok(BASE64.encode(&ciphertext))
    }

    /// Decrypt a private key with master key
    pub fn decrypt_private_key(
        &self,
        encrypted_pk_b64: &str,
        master_key: &[u8],
    ) -> AppResult<Vec<u8>> {
        let ciphertext = BASE64
            .decode(encrypted_pk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid encrypted key: {}", e)))?;

        decrypt_aes_gcm(&ciphertext, master_key)
            .map_err(|e| AppError::Crypto(format!("Private key decryption failed: {}", e)))
    }

    /// Encrypt a DEK with folder KEK
    pub fn encrypt_dek(&self, dek: &[u8], kek: &[u8]) -> AppResult<String> {
        let ciphertext = encrypt_aes_gcm(dek, kek)
            .map_err(|e| AppError::Crypto(format!("DEK encryption failed: {}", e)))?;

        Ok(BASE64.encode(&ciphertext))
    }

    /// Decrypt a DEK with folder KEK
    pub fn decrypt_dek(&self, encrypted_dek_b64: &str, kek: &[u8]) -> AppResult<Vec<u8>> {
        let ciphertext = BASE64
            .decode(encrypted_dek_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid encrypted DEK: {}", e)))?;

        decrypt_aes_gcm(&ciphertext, kek)
            .map_err(|e| AppError::Crypto(format!("DEK decryption failed: {}", e)))
    }

    /// Encrypt arbitrary data with the current master key
    pub fn encrypt_data(&self, data: &[u8]) -> AppResult<EncryptionResult> {
        let master_key = self.master_key.read();
        let master_key = master_key
            .as_ref()
            .ok_or_else(|| AppError::Crypto("Master key not loaded".to_string()))?;

        let ciphertext = encrypt_aes_gcm(data, master_key)
            .map_err(|e| AppError::Crypto(format!("Data encryption failed: {}", e)))?;

        // Split nonce and ciphertext
        let nonce = &ciphertext[..12];
        let ct = &ciphertext[12..];

        Ok(EncryptionResult {
            ciphertext: BASE64.encode(ct),
            nonce: BASE64.encode(nonce),
        })
    }

    /// Decrypt arbitrary data with the current master key
    pub fn decrypt_data(&self, ciphertext_b64: &str, nonce_b64: &str) -> AppResult<Vec<u8>> {
        let master_key = self.master_key.read();
        let master_key = master_key
            .as_ref()
            .ok_or_else(|| AppError::Crypto("Master key not loaded".to_string()))?;

        let ciphertext = BASE64
            .decode(ciphertext_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ciphertext: {}", e)))?;
        let nonce = BASE64
            .decode(nonce_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid nonce: {}", e)))?;

        let mut full_ciphertext = Vec::with_capacity(nonce.len() + ciphertext.len());
        full_ciphertext.extend_from_slice(&nonce);
        full_ciphertext.extend_from_slice(&ciphertext);

        decrypt_aes_gcm(&full_ciphertext, master_key)
            .map_err(|e| AppError::Crypto(format!("Data decryption failed: {}", e)))
    }

    /// Encrypt file data with a DEK
    pub fn encrypt_file_chunk(&self, chunk: &[u8], dek: &[u8]) -> AppResult<Vec<u8>> {
        encrypt_aes_gcm(chunk, dek)
            .map_err(|e| AppError::Crypto(format!("Chunk encryption failed: {}", e)))
    }

    /// Decrypt file data with a DEK
    pub fn decrypt_file_chunk(&self, encrypted_chunk: &[u8], dek: &[u8]) -> AppResult<Vec<u8>> {
        decrypt_aes_gcm(encrypted_chunk, dek)
            .map_err(|e| AppError::Crypto(format!("Chunk decryption failed: {}", e)))
    }

    // ==================== Signatures ====================

    /// Sign data with combined signature (ML-DSA + KAZ-SIGN)
    pub fn sign_data(&self, data: &[u8]) -> AppResult<SignatureResult> {
        // For now, we'll use ML-DSA only as primary
        // In production, we'd combine both signatures

        // This would require the user's signing private key
        // For now, return a placeholder
        Err(AppError::Crypto(
            "Signing requires loaded private key".to_string(),
        ))
    }

    /// Sign data with specific private key
    pub fn sign_with_key(
        &self,
        data: &[u8],
        ml_dsa_sk_b64: &str,
        kaz_sign_sk_b64: &str,
    ) -> AppResult<SignatureResult> {
        let ml_dsa_sk = BASE64
            .decode(ml_dsa_sk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-DSA key: {}", e)))?;

        let kaz_sign_sk = BASE64
            .decode(kaz_sign_sk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid KAZ-SIGN key: {}", e)))?;

        // Sign with ML-DSA
        let ml_dsa_sig = ml_dsa::sign(data, &ml_dsa_sk)
            .map_err(|e| AppError::Crypto(format!("ML-DSA signing failed: {}", e)))?;

        // Sign with KAZ-SIGN
        let kaz_sign_sig = kaz_sign::sign(data, &kaz_sign_sk, kaz_sign::SecurityLevel::Level256)
            .map_err(|e| AppError::Crypto(format!("KAZ-SIGN signing failed: {}", e)))?;

        // Combine signatures
        let combined_sig = [ml_dsa_sig, kaz_sign_sig].concat();

        Ok(SignatureResult {
            signature: BASE64.encode(&combined_sig),
            algorithm: "ML-DSA-65+KAZ-SIGN-256".to_string(),
        })
    }

    /// Verify signature
    pub fn verify_signature(
        &self,
        data: &[u8],
        signature_b64: &str,
        ml_dsa_pk_b64: &str,
        kaz_sign_pk_b64: &str,
    ) -> AppResult<bool> {
        let signature = BASE64
            .decode(signature_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid signature: {}", e)))?;

        let ml_dsa_pk = BASE64
            .decode(ml_dsa_pk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-DSA public key: {}", e)))?;

        let kaz_sign_pk = BASE64
            .decode(kaz_sign_pk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid KAZ-SIGN public key: {}", e)))?;

        // Split combined signature
        // ML-DSA-65 signature is approximately 3309 bytes
        // This split point would need to be determined by actual signature sizes
        let ml_dsa_sig_len = ml_dsa::SIGNATURE_SIZE;
        if signature.len() < ml_dsa_sig_len {
            return Err(AppError::Crypto("Signature too short".to_string()));
        }

        let (ml_dsa_sig, kaz_sign_sig) = signature.split_at(ml_dsa_sig_len);

        // Verify ML-DSA
        let ml_dsa_valid = ml_dsa::verify(data, ml_dsa_sig, &ml_dsa_pk)
            .map_err(|e| AppError::Crypto(format!("ML-DSA verification failed: {}", e)))?;

        // Verify KAZ-SIGN - returns extracted message on success
        // Use constant-time comparison to prevent timing attacks
        use subtle::ConstantTimeEq;
        let kaz_sign_valid = kaz_sign::verify(kaz_sign_sig, &kaz_sign_pk, kaz_sign::SecurityLevel::Level256)
            .map(|recovered| {
                // Constant-time comparison of recovered message with original data
                if recovered.len() != data.len() {
                    false
                } else {
                    recovered.ct_eq(data).into()
                }
            })
            .unwrap_or(false);

        Ok(ml_dsa_valid && kaz_sign_valid)
    }

    // ==================== Key Encapsulation ====================

    /// Encapsulate a shared secret for a recipient
    pub fn encapsulate(
        &self,
        ml_kem_pk_b64: &str,
        kaz_kem_pk_b64: &str,
    ) -> AppResult<(String, Vec<u8>)> {
        let ml_kem_pk = BASE64
            .decode(ml_kem_pk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-KEM public key: {}", e)))?;

        let kaz_kem_pk = BASE64
            .decode(kaz_kem_pk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid KAZ-KEM public key: {}", e)))?;

        // Encapsulate with ML-KEM
        let ml_encap = ml_kem::encapsulate(&ml_kem_pk)
            .map_err(|e| AppError::Crypto(format!("ML-KEM encapsulation failed: {}", e)))?;

        // Encapsulate with KAZ-KEM
        let kaz_encap = kaz_kem::encapsulate(&kaz_kem_pk)
            .map_err(|e| AppError::Crypto(format!("KAZ-KEM encapsulation failed: {}", e)))?;

        // Combine ciphertexts
        let combined_ct = [ml_encap.ciphertext.clone(), kaz_encap.ciphertext.clone()].concat();

        // Combine shared secrets using HKDF
        let combined_ss = [ml_encap.shared_secret.clone(), kaz_encap.shared_secret.clone()].concat();
        let final_ss = hkdf_derive(&combined_ss, None, b"combined-kem", KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("HKDF failed: {}", e)))?;

        Ok((BASE64.encode(&combined_ct), final_ss))
    }

    /// Decapsulate a shared secret
    pub fn decapsulate(
        &self,
        ciphertext_b64: &str,
        ml_kem_sk_b64: &str,
        kaz_kem_sk_b64: &str,
    ) -> AppResult<Vec<u8>> {
        let ciphertext = BASE64
            .decode(ciphertext_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ciphertext: {}", e)))?;

        let ml_kem_sk = BASE64
            .decode(ml_kem_sk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-KEM secret key: {}", e)))?;

        let kaz_kem_sk = BASE64
            .decode(kaz_kem_sk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid KAZ-KEM secret key: {}", e)))?;

        // Split ciphertext
        let ml_kem_ct_len = ml_kem::CIPHERTEXT_SIZE;
        if ciphertext.len() < ml_kem_ct_len {
            return Err(AppError::Crypto("Ciphertext too short".to_string()));
        }

        let (ml_kem_ct, kaz_kem_ct) = ciphertext.split_at(ml_kem_ct_len);

        // Decapsulate ML-KEM
        let ml_ss = ml_kem::decapsulate(ml_kem_ct, &ml_kem_sk)
            .map_err(|e| AppError::Crypto(format!("ML-KEM decapsulation failed: {}", e)))?;

        // Decapsulate KAZ-KEM
        let kaz_ss = kaz_kem::decapsulate(kaz_kem_ct, &kaz_kem_sk)
            .map_err(|e| AppError::Crypto(format!("KAZ-KEM decapsulation failed: {}", e)))?;

        // Combine shared secrets
        let combined_ss = [ml_ss, kaz_ss].concat();
        hkdf_derive(&combined_ss, None, b"combined-kem", KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("HKDF failed: {}", e)))
    }
}

impl Drop for CryptoService {
    fn drop(&mut self) {
        self.clear_master_key();
        ssdid_drive_crypto::cleanup();
    }
}
