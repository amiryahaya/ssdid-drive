//! Cryptographic operation commands

use crate::error::AppResult;
use crate::state::AppState;
use base64::Engine;
use serde::{Deserialize, Serialize};
use tauri::State;
use zeroize::Zeroize;

/// Generated key pair response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyPairResponse {
    /// Base64-encoded public key
    pub public_key: String,
    /// Algorithm identifier
    pub algorithm: String,
}

/// Encryption result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptionResult {
    /// Base64-encoded ciphertext
    pub ciphertext: String,
    /// Base64-encoded nonce
    pub nonce: String,
}

/// Signature result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignatureResult {
    /// Base64-encoded signature
    pub signature: String,
    /// Algorithm used
    pub algorithm: String,
}

/// Verification result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    /// Whether the signature is valid
    pub is_valid: bool,
}

/// Generate a new key pair (for testing/debugging)
#[tauri::command]
pub async fn generate_keys(
    algorithm: String,
    state: State<'_, AppState>,
) -> AppResult<KeyPairResponse> {
    tracing::info!("Generating key pair for algorithm: {}", algorithm);

    let (public_key, _secret_key) = match algorithm.as_str() {
        "ml-kem-768" => state.crypto_service().generate_ml_kem_keypair()?,
        "ml-dsa-65" => state.crypto_service().generate_ml_dsa_keypair()?,
        "kaz-kem-256" => state.crypto_service().generate_kaz_kem_keypair()?,
        "kaz-sign-256" => state.crypto_service().generate_kaz_sign_keypair()?,
        _ => {
            return Err(crate::error::AppError::Validation(format!(
                "Unknown algorithm: {}",
                algorithm
            )))
        }
    };

    Ok(KeyPairResponse {
        public_key,
        algorithm,
    })
}

/// Encrypt data with the user's key
#[tauri::command]
pub async fn encrypt_data(data: String, state: State<'_, AppState>) -> AppResult<EncryptionResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Encrypting {} bytes of data", data.len());

    let result = state.crypto_service().encrypt_data(data.as_bytes())?;

    Ok(result)
}

/// Decrypt data with the user's key
#[tauri::command]
pub async fn decrypt_data(
    ciphertext: String,
    nonce: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Decrypting data");

    let plaintext = state.crypto_service().decrypt_data(&ciphertext, &nonce)?;

    Ok(String::from_utf8_lossy(&plaintext).to_string())
}

/// Sign data with the user's signing key
#[tauri::command]
pub async fn sign_data(data: String, state: State<'_, AppState>) -> AppResult<SignatureResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Signing {} bytes of data", data.len());

    // In the SSDID model, signing is handled by the wallet.
    // The desktop app no longer holds private signing keys.
    let result = state.crypto_service().sign_data(data.as_bytes())?;

    Ok(result)
}

/// User's KEM public keys response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserKemPublicKeys {
    pub ml_kem_pk: String,
    pub kaz_kem_pk: String,
}

/// Get the current user's KEM public keys (for folder key encapsulation)
#[tauri::command]
pub async fn get_user_kem_public_keys(
    state: State<'_, AppState>,
) -> AppResult<UserKemPublicKeys> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting user KEM public keys");

    // Fetch public keys from local database settings
    let ml_kem_pk = state
        .database()
        .get_setting("ml_kem_pk")?
        .ok_or_else(|| crate::error::AppError::Crypto("ML-KEM public key not found".to_string()))?;

    let kaz_kem_pk = state
        .database()
        .get_setting("kaz_kem_pk")?
        .ok_or_else(|| crate::error::AppError::Crypto("KAZ-KEM public key not found".to_string()))?;

    Ok(UserKemPublicKeys {
        ml_kem_pk,
        kaz_kem_pk,
    })
}

/// Verify a combined signature (ML-DSA-65 + KAZ-SIGN-256)
#[tauri::command]
pub async fn verify_signature(
    data: String,
    signature: String,
    ml_dsa_pk: String,
    kaz_sign_pk: String,
    state: State<'_, AppState>,
) -> AppResult<VerificationResult> {
    tracing::debug!("Verifying combined signature");

    let is_valid = state
        .crypto_service()
        .verify_signature(data.as_bytes(), &signature, &ml_dsa_pk, &kaz_sign_pk)?;

    Ok(VerificationResult { is_valid })
}

// ==================== File Encryption Commands ====================

/// Generated KEM key pair response with encrypted private key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KemKeyPairResponse {
    /// Base64-encoded public key
    pub public_key: String,
    /// Base64-encoded encrypted private key (encrypted with master key)
    pub encrypted_private_key: String,
    /// Algorithm identifier
    pub algorithm: String,
}

/// Generate a KEM key pair and encrypt the private key with the master key.
///
/// Returns the public key and the encrypted private key for safe storage.
#[tauri::command]
pub async fn generate_kem_keypair(
    algorithm: String,
    state: State<'_, AppState>,
) -> AppResult<KemKeyPairResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Generating KEM key pair for algorithm: {}", algorithm);

    let (public_key, secret_key) = match algorithm.as_str() {
        "ml-kem-768" => state.crypto_service().generate_ml_kem_keypair()?,
        "kaz-kem-256" => state.crypto_service().generate_kaz_kem_keypair()?,
        _ => {
            return Err(crate::error::AppError::Validation(format!(
                "Unknown KEM algorithm: {}. Supported: ml-kem-768, kaz-kem-256",
                algorithm
            )))
        }
    };

    // Encrypt the private key with the master key for safe storage
    let master_key = state.crypto_service().get_master_key()?;
    let encrypted_private_key = state
        .crypto_service()
        .encrypt_private_key(&secret_key, &master_key)?;

    Ok(KemKeyPairResponse {
        public_key,
        encrypted_private_key,
        algorithm,
    })
}

/// File encryption result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEncryptionResult {
    /// Path to the encrypted ciphertext file
    pub ciphertext_path: String,
    /// Base64-encoded encrypted file key (wrapped with folder key)
    pub encrypted_file_key: String,
    /// Base64-encoded nonce (included in ciphertext, returned for metadata)
    pub nonce: String,
}

/// Encrypt a file using a folder key.
///
/// Derives a file-specific key from the folder key using HKDF,
/// encrypts the file with AES-256-GCM, and writes the ciphertext
/// to a `.enc` file alongside the original.
///
/// The folder_key parameter is base64-encoded.
#[tauri::command]
pub async fn encrypt_file(
    file_path: String,
    folder_key: String,
    file_id: String,
    state: State<'_, AppState>,
) -> AppResult<FileEncryptionResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Encrypting file: {}", file_path);

    let result = state
        .crypto_service()
        .encrypt_file_to_path(&file_path, &folder_key, &file_id)?;

    Ok(result)
}

/// File decryption result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDecryptionResult {
    /// Path to the decrypted plaintext file
    pub plaintext_path: String,
}

/// Decrypt a file using a folder key.
///
/// Derives the file-specific key from the folder key using HKDF,
/// decrypts the ciphertext file, and writes the plaintext to disk.
///
/// The folder_key parameter is base64-encoded.
#[tauri::command]
pub async fn decrypt_file(
    ciphertext_path: String,
    folder_key: String,
    file_id: String,
    state: State<'_, AppState>,
) -> AppResult<FileDecryptionResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Decrypting file: {}", ciphertext_path);

    let result = state
        .crypto_service()
        .decrypt_file_from_path(&ciphertext_path, &folder_key, &file_id)?;

    Ok(result)
}

/// Folder key encapsulation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderKeyEncapsulationResult {
    /// Base64-encoded KEM ciphertext (ML-KEM + KAZ-KEM combined)
    pub kem_ciphertext: String,
    /// Base64-encoded AES-wrapped folder key
    pub wrapped_folder_key: String,
    /// Algorithm identifier
    pub algorithm: String,
}

/// Encapsulate a folder key for a recipient using their KEM public keys.
///
/// Uses hybrid KEM (ML-KEM-768 + KAZ-KEM-256) to encapsulate a shared secret,
/// then AES-wraps the folder key with that shared secret.
///
/// All parameters are base64-encoded.
#[tauri::command]
pub async fn encapsulate_folder_key(
    folder_key: String,
    recipient_ml_kem_pk: String,
    recipient_kaz_kem_pk: String,
    state: State<'_, AppState>,
) -> AppResult<FolderKeyEncapsulationResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Encapsulating folder key for recipient");

    let folder_key_bytes = base64::engine::general_purpose::STANDARD
        .decode(&folder_key)
        .map_err(|e| crate::error::AppError::Crypto(format!("Invalid folder key: {}", e)))?;

    let (kem_ciphertext, wrapped_folder_key, algorithm) = state
        .crypto_service()
        .encapsulate_folder_key(&folder_key_bytes, &recipient_ml_kem_pk, &recipient_kaz_kem_pk)?;

    Ok(FolderKeyEncapsulationResult {
        kem_ciphertext,
        wrapped_folder_key,
        algorithm,
    })
}

/// Folder key decapsulation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderKeyDecapsulationResult {
    /// Base64-encoded plaintext folder key
    pub folder_key: String,
}

/// Decapsulate and unwrap a folder key using the user's private KEM keys.
///
/// Uses the encrypted private keys stored locally (decrypted with master key)
/// to recover the shared secret via hybrid KEM, then AES-unwraps the folder key.
///
/// All parameters are base64-encoded.
#[tauri::command]
pub async fn decapsulate_folder_key(
    kem_ciphertext: String,
    wrapped_folder_key: String,
    encrypted_ml_kem_sk: String,
    encrypted_kaz_kem_sk: String,
    state: State<'_, AppState>,
) -> AppResult<FolderKeyDecapsulationResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Decapsulating folder key");

    // Decrypt private keys with master key
    let master_key = state.crypto_service().get_master_key()?;
    let mut ml_kem_sk = state
        .crypto_service()
        .decrypt_private_key(&encrypted_ml_kem_sk, &master_key)?;
    let mut kaz_kem_sk = state
        .crypto_service()
        .decrypt_private_key(&encrypted_kaz_kem_sk, &master_key)?;

    let ml_kem_sk_b64 = base64::engine::general_purpose::STANDARD.encode(&ml_kem_sk);
    let kaz_kem_sk_b64 = base64::engine::general_purpose::STANDARD.encode(&kaz_kem_sk);

    // Zeroize decrypted private key bytes
    ml_kem_sk.zeroize();
    kaz_kem_sk.zeroize();

    let folder_key = state.crypto_service().decapsulate_folder_key(
        &kem_ciphertext,
        &wrapped_folder_key,
        &ml_kem_sk_b64,
        &kaz_kem_sk_b64,
    )?;

    Ok(FolderKeyDecapsulationResult {
        folder_key: base64::engine::general_purpose::STANDARD.encode(&folder_key),
    })
}

/// File key derivation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DerivedFileKeyResult {
    /// Base64-encoded derived file key (32 bytes)
    pub file_key: String,
}

/// Derive a file-specific encryption key from a folder key and file ID.
///
/// Uses HKDF-SHA256 with the folder key as IKM and a domain-separated
/// info string incorporating the file ID.
///
/// The folder_key parameter is base64-encoded.
#[tauri::command]
pub async fn derive_file_key(
    folder_key: String,
    file_id: String,
    state: State<'_, AppState>,
) -> AppResult<DerivedFileKeyResult> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Deriving file key for file: {}", file_id);

    let folder_key_bytes = base64::engine::general_purpose::STANDARD
        .decode(&folder_key)
        .map_err(|e| crate::error::AppError::Crypto(format!("Invalid folder key: {}", e)))?;

    let file_key = state
        .crypto_service()
        .derive_file_key(&folder_key_bytes, &file_id)?;

    Ok(DerivedFileKeyResult {
        file_key: base64::engine::general_purpose::STANDARD.encode(&file_key),
    })
}
