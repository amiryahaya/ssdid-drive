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
use zeroize::Zeroizing;

/// Service for cryptographic operations
pub struct CryptoService {
    initialized: bool,
    /// Current master key (in memory, zeroized on drop)
    master_key: RwLock<Option<Zeroizing<Vec<u8>>>>,
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
        *self.master_key.write() = Some(Zeroizing::new(key));
        Ok(())
    }

    /// Clear the master key from memory
    pub fn clear_master_key(&self) {
        // Zeroizing handles zeroization on drop automatically
        self.master_key.write().take();
    }

    /// Check if master key is loaded
    pub fn has_master_key(&self) -> bool {
        self.master_key.read().is_some()
    }

    /// Get a clone of the master key (for recovery setup)
    /// This is a security-sensitive operation - use carefully
    pub fn get_master_key(&self) -> AppResult<Zeroizing<Vec<u8>>> {
        self.master_key
            .read()
            .as_ref()
            .cloned()
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
    pub fn generate_master_key(&self) -> AppResult<Zeroizing<Vec<u8>>> {
        Ok(generate_key())
    }

    /// Generate a Data Encryption Key (DEK)
    pub fn generate_dek(&self) -> AppResult<Zeroizing<Vec<u8>>> {
        Ok(generate_key())
    }

    // ==================== Key Derivation ====================

    /// Derive authentication key from password using tiered KDF.
    /// Desktop always uses Argon2idStandard for new salts.
    pub fn derive_auth_key(&self, password: &str) -> AppResult<(String, String)> {
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idStandard);

        let key = tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))?;

        // key is Zeroizing<Vec<u8>>, encode then it auto-zeroizes on drop
        Ok((BASE64.encode(&salt), BASE64.encode(&*key)))
    }

    /// Derive encryption key from password and existing salt.
    /// Automatically detects tiered vs legacy salt format.
    pub fn derive_encryption_key(&self, password: &str, salt_b64: &str) -> AppResult<Zeroizing<Vec<u8>>> {
        let salt = BASE64
            .decode(salt_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid salt: {}", e)))?;

        tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))
    }

    /// Derive encryption key with new salt using tiered KDF.
    /// Desktop always uses Argon2idStandard for new salts.
    pub fn derive_encryption_key_with_salt(&self, password: &str) -> AppResult<(String, Zeroizing<Vec<u8>>)> {
        let salt = tiered_kdf_create_salt(KdfProfile::Argon2idStandard);

        let key = tiered_kdf_derive(password.as_bytes(), &salt)
            .map_err(|e| AppError::Crypto(format!("KDF derivation failed: {}", e)))?;

        Ok((BASE64.encode(&salt), key))
    }

    /// Derive a folder Key Encryption Key (KEK) from master key
    pub fn derive_folder_kek(&self, folder_id: &str) -> AppResult<Zeroizing<Vec<u8>>> {
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
    ) -> AppResult<Zeroizing<Vec<u8>>> {
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
        let pk_bytes = Zeroizing::new(
            BASE64
                .decode(private_key)
                .map_err(|e| AppError::Crypto(format!("Invalid private key: {}", e)))?,
        );

        let result = encrypt_aes_gcm(&pk_bytes, master_key)
            .map_err(|e| AppError::Crypto(format!("Private key encryption failed: {}", e)))?;

        // pk_bytes auto-zeroizes on drop
        Ok(BASE64.encode(&result))
    }

    /// Decrypt a private key with master key
    pub fn decrypt_private_key(
        &self,
        encrypted_pk_b64: &str,
        master_key: &[u8],
    ) -> AppResult<Zeroizing<Vec<u8>>> {
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
    pub fn decrypt_dek(&self, encrypted_dek_b64: &str, kek: &[u8]) -> AppResult<Zeroizing<Vec<u8>>> {
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
    pub fn decrypt_data(&self, ciphertext_b64: &str, nonce_b64: &str) -> AppResult<Zeroizing<Vec<u8>>> {
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
    pub fn decrypt_file_chunk(&self, encrypted_chunk: &[u8], dek: &[u8]) -> AppResult<Zeroizing<Vec<u8>>> {
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
        let ml_dsa_decode = BASE64.decode(ml_dsa_sk_b64);
        let kaz_sign_decode = BASE64.decode(kaz_sign_sk_b64);

        let ml_dsa_sk = Zeroizing::new(
            ml_dsa_decode
                .map_err(|e| AppError::Crypto(format!("Invalid ML-DSA key: {}", e)))?,
        );

        let kaz_sign_sk = Zeroizing::new(
            kaz_sign_decode
                .map_err(|e| AppError::Crypto(format!("Invalid KAZ-SIGN key: {}", e)))?,
        );

        // Sign with ML-DSA
        let ml_dsa_result = ml_dsa::sign(data, &ml_dsa_sk)
            .map_err(|e| AppError::Crypto(format!("ML-DSA signing failed: {}", e)));

        // Sign with KAZ-SIGN
        let kaz_sign_result = kaz_sign::sign(data, &kaz_sign_sk, kaz_sign::SecurityLevel::Level256)
            .map_err(|e| AppError::Crypto(format!("KAZ-SIGN signing failed: {}", e)));

        // ml_dsa_sk and kaz_sign_sk auto-zeroize on drop

        let ml_dsa_sig = ml_dsa_result?;
        let kaz_sign_sig = kaz_sign_result?;

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

    // ==================== Folder Key Management ====================

    /// Generate a random 256-bit folder key
    pub fn generate_folder_key(&self) -> AppResult<Zeroizing<Vec<u8>>> {
        Ok(generate_key())
    }

    /// Generate a random 256-bit file key
    pub fn generate_file_key(&self) -> AppResult<Zeroizing<Vec<u8>>> {
        Ok(generate_key())
    }

    /// Derive a deterministic file key from a folder key and file ID using HKDF-SHA256.
    ///
    /// This allows deriving a unique per-file key without storing it separately.
    /// The folder key acts as the input keying material (IKM), and the file ID
    /// is used as the info parameter for domain separation.
    pub fn derive_file_key(&self, folder_key: &[u8], file_id: &str) -> AppResult<Zeroizing<Vec<u8>>> {
        if folder_key.len() != KEY_SIZE {
            return Err(AppError::Crypto(format!(
                "Invalid folder key size: expected {}, got {}",
                KEY_SIZE,
                folder_key.len()
            )));
        }

        let info = format!("ssdid-drive:file-key:{}", file_id);
        hkdf_derive(folder_key, None, info.as_bytes(), KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("File key derivation failed: {}", e)))
    }

    /// Encrypt a file on disk using a folder key and file ID.
    ///
    /// 1. Derives a file-specific key from the folder key via HKDF
    /// 2. Reads the plaintext file
    /// 3. Encrypts with AES-256-GCM
    /// 4. Writes ciphertext to `<file_path>.enc`
    /// 5. Returns the ciphertext path, encrypted file key, and nonce
    pub fn encrypt_file_to_path(
        &self,
        file_path: &str,
        folder_key_b64: &str,
        file_id: &str,
    ) -> AppResult<crate::commands::crypto::FileEncryptionResult> {
        use std::io::{Read, Write};

        let folder_key = Zeroizing::new(
            BASE64
                .decode(folder_key_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid folder key: {}", e)))?,
        );

        // Derive a file-specific key from the folder key
        let file_key = self.derive_file_key(&folder_key, file_id)?;

        // Read plaintext file
        let path = std::path::Path::new(file_path);
        if !path.exists() {
            return Err(AppError::File(format!("File not found: {}", file_path)));
        }
        let mut plaintext = Vec::new();
        std::fs::File::open(path)
            .map_err(|e| AppError::File(format!("Failed to open file: {}", e)))
            .and_then(|mut f| {
                f.read_to_end(&mut plaintext)
                    .map_err(|e| AppError::File(format!("Failed to read file: {}", e)))
            })?;

        // Encrypt with AES-256-GCM (returns nonce || ciphertext || tag)
        let ciphertext = encrypt_aes_gcm(&plaintext, &file_key)
            .map_err(|e| AppError::Crypto(format!("File encryption failed: {}", e)))?;

        // Extract nonce from the ciphertext (first 12 bytes)
        let nonce = &ciphertext[..12];
        let nonce_b64 = BASE64.encode(nonce);

        // Wrap the file key with the folder key for storage
        let encrypted_file_key = self.wrap_key(&file_key, &folder_key)?;

        // folder_key and file_key auto-zeroize on drop

        // Write ciphertext to <file_path>.enc
        let ciphertext_path = format!("{}.enc", file_path);
        let mut output = std::fs::File::create(&ciphertext_path)
            .map_err(|e| AppError::File(format!("Failed to create encrypted file: {}", e)))?;
        output
            .write_all(&ciphertext)
            .map_err(|e| AppError::File(format!("Failed to write encrypted file: {}", e)))?;
        output
            .flush()
            .map_err(|e| AppError::File(format!("Failed to flush encrypted file: {}", e)))?;

        Ok(crate::commands::crypto::FileEncryptionResult {
            ciphertext_path,
            encrypted_file_key,
            nonce: nonce_b64,
        })
    }

    /// Decrypt a file on disk using a folder key and file ID.
    ///
    /// 1. Derives the file-specific key from the folder key via HKDF
    /// 2. Reads the ciphertext file
    /// 3. Decrypts with AES-256-GCM
    /// 4. Writes plaintext to disk (strips `.enc` extension or appends `.dec`)
    /// 5. Returns the plaintext path
    pub fn decrypt_file_from_path(
        &self,
        ciphertext_path: &str,
        folder_key_b64: &str,
        file_id: &str,
    ) -> AppResult<crate::commands::crypto::FileDecryptionResult> {
        use std::io::{Read, Write};

        let folder_key = Zeroizing::new(
            BASE64
                .decode(folder_key_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid folder key: {}", e)))?,
        );

        // Derive the same file-specific key from the folder key
        let file_key = self.derive_file_key(&folder_key, file_id)?;
        // folder_key auto-zeroizes on drop

        // Read ciphertext file
        let path = std::path::Path::new(ciphertext_path);
        if !path.exists() {
            return Err(AppError::File(format!(
                "Ciphertext file not found: {}",
                ciphertext_path
            )));
        }
        let mut ciphertext = Vec::new();
        std::fs::File::open(path)
            .map_err(|e| AppError::File(format!("Failed to open ciphertext file: {}", e)))
            .and_then(|mut f| {
                f.read_to_end(&mut ciphertext)
                    .map_err(|e| AppError::File(format!("Failed to read ciphertext file: {}", e)))
            })?;

        // Decrypt with AES-256-GCM (expects nonce || ciphertext || tag)
        let plaintext = decrypt_aes_gcm(&ciphertext, &file_key)
            .map_err(|e| AppError::Crypto(format!("File decryption failed: {}", e)))?;

        // file_key auto-zeroizes on drop

        // Determine output path: strip .enc extension or append .dec
        let plaintext_path = if ciphertext_path.ends_with(".enc") {
            ciphertext_path[..ciphertext_path.len() - 4].to_string()
        } else {
            format!("{}.dec", ciphertext_path)
        };

        // Write plaintext to disk
        let mut output = std::fs::File::create(&plaintext_path)
            .map_err(|e| AppError::File(format!("Failed to create output file: {}", e)))?;
        output
            .write_all(&plaintext)
            .map_err(|e| AppError::File(format!("Failed to write output file: {}", e)))?;
        output
            .flush()
            .map_err(|e| AppError::File(format!("Failed to flush output file: {}", e)))?;

        // plaintext (Zeroizing<Vec<u8>>) auto-zeroizes on drop

        Ok(crate::commands::crypto::FileDecryptionResult { plaintext_path })
    }

    /// Encrypt a file's content with AES-256-GCM using a file key.
    /// Returns (nonce || ciphertext_with_tag).
    pub fn encrypt_file_content(&self, plaintext: &[u8], key: &[u8]) -> AppResult<Vec<u8>> {
        encrypt_aes_gcm(plaintext, key)
            .map_err(|e| AppError::Crypto(format!("File encryption failed: {}", e)))
    }

    /// Decrypt a file's content with AES-256-GCM using a file key.
    /// Expects (nonce || ciphertext_with_tag).
    pub fn decrypt_file_content(&self, ciphertext: &[u8], key: &[u8]) -> AppResult<Zeroizing<Vec<u8>>> {
        decrypt_aes_gcm(ciphertext, key)
            .map_err(|e| AppError::Crypto(format!("File decryption failed: {}", e)))
    }

    /// Wrap a key (e.g., file key) with a wrapping key (e.g., folder key) using AES-256-GCM.
    /// Returns base64-encoded (nonce || ciphertext_with_tag).
    pub fn wrap_key(&self, key_to_wrap: &[u8], wrapping_key: &[u8]) -> AppResult<String> {
        let wrapped = encrypt_aes_gcm(key_to_wrap, wrapping_key)
            .map_err(|e| AppError::Crypto(format!("Key wrapping failed: {}", e)))?;
        Ok(BASE64.encode(&wrapped))
    }

    /// Unwrap a key using AES-256-GCM.
    /// Input is base64-encoded (nonce || ciphertext_with_tag).
    pub fn unwrap_key(&self, wrapped_key_b64: &str, wrapping_key: &[u8]) -> AppResult<Zeroizing<Vec<u8>>> {
        let wrapped = BASE64
            .decode(wrapped_key_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid wrapped key: {}", e)))?;
        decrypt_aes_gcm(&wrapped, wrapping_key)
            .map_err(|e| AppError::Crypto(format!("Key unwrapping failed: {}", e)))
    }

    /// Encapsulate a folder key for storage: KEM-encapsulate to get shared secret,
    /// then AES-wrap the folder key with that shared secret.
    /// Returns (kem_ciphertext_b64, wrapped_folder_key_b64, algorithm).
    pub fn encapsulate_folder_key(
        &self,
        folder_key: &[u8],
        ml_kem_pk_b64: &str,
        kaz_kem_pk_b64: &str,
    ) -> AppResult<(String, String, String)> {
        let (kem_ct_b64, shared_secret) = self.encapsulate(ml_kem_pk_b64, kaz_kem_pk_b64)?;

        // AES-wrap the folder key with the KEM shared secret
        let wrapped_folder_key_b64 = self.wrap_key(folder_key, &shared_secret)?;

        // shared_secret auto-zeroizes on drop

        Ok((kem_ct_b64, wrapped_folder_key_b64, "ML-KEM-768+KAZ-KEM-256".to_string()))
    }

    /// Decapsulate and unwrap a folder key.
    /// Returns the plaintext folder key.
    pub fn decapsulate_folder_key(
        &self,
        kem_ct_b64: &str,
        wrapped_folder_key_b64: &str,
        ml_kem_sk_b64: &str,
        kaz_kem_sk_b64: &str,
    ) -> AppResult<Zeroizing<Vec<u8>>> {
        let shared_secret = self.decapsulate(kem_ct_b64, ml_kem_sk_b64, kaz_kem_sk_b64)?;

        // Unwrap the folder key
        let folder_key = self.unwrap_key(wrapped_folder_key_b64, &shared_secret)?;

        // shared_secret auto-zeroizes on drop

        Ok(folder_key)
    }

    /// Re-encapsulate a folder key for a new recipient (used in sharing).
    /// Decapsulates with owner's keys, then encapsulates with recipient's keys.
    pub fn re_encapsulate_folder_key(
        &self,
        kem_ct_b64: &str,
        wrapped_folder_key_b64: &str,
        owner_ml_kem_sk_b64: &str,
        owner_kaz_kem_sk_b64: &str,
        recipient_ml_kem_pk_b64: &str,
        recipient_kaz_kem_pk_b64: &str,
    ) -> AppResult<(String, String, String)> {
        // Decrypt folder key with owner's private keys
        let folder_key = self.decapsulate_folder_key(
            kem_ct_b64,
            wrapped_folder_key_b64,
            owner_ml_kem_sk_b64,
            owner_kaz_kem_sk_b64,
        )?;

        // Re-encapsulate for recipient
        // folder_key auto-zeroizes on drop
        self.encapsulate_folder_key(
            &folder_key,
            recipient_ml_kem_pk_b64,
            recipient_kaz_kem_pk_b64,
        )
    }

    // ==================== Key Encapsulation ====================

    /// Encapsulate a shared secret for a recipient
    pub fn encapsulate(
        &self,
        ml_kem_pk_b64: &str,
        kaz_kem_pk_b64: &str,
    ) -> AppResult<(String, Zeroizing<Vec<u8>>)> {
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
        let combined_ss = Zeroizing::new(
            [ml_encap.shared_secret.clone(), kaz_encap.shared_secret.clone()].concat(),
        );
        let final_ss = hkdf_derive(&combined_ss, None, b"combined-kem", KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("HKDF failed: {}", e)))?;
        // combined_ss auto-zeroizes on drop

        Ok((BASE64.encode(&combined_ct), final_ss))
    }

    /// Decapsulate a shared secret
    pub fn decapsulate(
        &self,
        ciphertext_b64: &str,
        ml_kem_sk_b64: &str,
        kaz_kem_sk_b64: &str,
    ) -> AppResult<Zeroizing<Vec<u8>>> {
        let ciphertext = BASE64
            .decode(ciphertext_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ciphertext: {}", e)))?;

        let ml_kem_sk = Zeroizing::new(
            BASE64
                .decode(ml_kem_sk_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid ML-KEM secret key: {}", e)))?,
        );

        let kaz_kem_sk = Zeroizing::new(
            BASE64
                .decode(kaz_kem_sk_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid KAZ-KEM secret key: {}", e)))?,
        );

        // Split ciphertext
        let ml_kem_ct_len = ml_kem::CIPHERTEXT_SIZE;
        if ciphertext.len() < ml_kem_ct_len {
            return Err(AppError::Crypto("Ciphertext too short".to_string()));
        }

        let (ml_kem_ct, kaz_kem_ct) = ciphertext.split_at(ml_kem_ct_len);

        // Decapsulate ML-KEM -- now returns Zeroizing<Vec<u8>>
        let ml_ss = ml_kem::decapsulate(ml_kem_ct, &ml_kem_sk)
            .map_err(|e| AppError::Crypto(format!("ML-KEM decapsulation failed: {}", e)))?;

        // Decapsulate KAZ-KEM -- now returns Zeroizing<Vec<u8>>
        let kaz_ss = kaz_kem::decapsulate(kaz_kem_ct, &kaz_kem_sk)
            .map_err(|e| AppError::Crypto(format!("KAZ-KEM decapsulation failed: {}", e)))?;

        // ml_kem_sk and kaz_kem_sk auto-zeroize on drop

        // Combine shared secrets
        let combined_ss = Zeroizing::new([&ml_ss[..], &kaz_ss[..]].concat());
        // ml_ss and kaz_ss auto-zeroize on drop

        hkdf_derive(&combined_ss, None, b"combined-kem", KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("HKDF failed: {}", e)))
        // combined_ss auto-zeroizes on drop
    }
}

impl Drop for CryptoService {
    fn drop(&mut self) {
        // master_key is Zeroizing<Vec<u8>> inside Option, auto-zeroizes on drop
        self.master_key.write().take();
        ssdid_drive_crypto::cleanup();
    }
}
