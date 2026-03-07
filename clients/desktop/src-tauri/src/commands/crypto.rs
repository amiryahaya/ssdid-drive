//! Cryptographic operation commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

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
