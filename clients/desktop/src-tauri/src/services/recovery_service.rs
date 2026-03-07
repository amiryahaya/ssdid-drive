//! Recovery key management service
//!
//! Implements Shamir secret sharing for key recovery, allowing users to
//! designate trustees who can help recover their account if they lose
//! their password.

use crate::error::{AppError, AppResult};
use crate::models::{
    InitiateRecoveryRequest, RecipientPublicKeys, RecoveryRequest,
    RecoverySetup, SetupRecoveryRequest,
};
use crate::services::{ApiClient, CryptoService};
use crate::storage::Database;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use securesharing_crypto::shamir::{self, Share};
use securesharing_crypto::symmetric::{encrypt_aes_gcm, decrypt_aes_gcm, KEY_SIZE};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Recovery service for managing account recovery with trustees
pub struct RecoveryService {
    api_client: Arc<ApiClient>,
    crypto_service: Arc<CryptoService>,
    database: Arc<Database>,
}

/// Trustee lookup result from API
#[derive(Debug, Clone, Serialize, Deserialize)]
struct TrusteeLookup {
    pub id: String,
    pub email: String,
    pub name: String,
    pub public_keys: RecipientPublicKeys,
}

/// Recovery setup API request
#[derive(Debug, Clone, Serialize, Deserialize)]
struct RecoverySetupApiRequest {
    pub threshold: u32,
    pub encrypted_shares: Vec<EncryptedTrusteeShare>,
    /// Verification ciphertext for validating reconstructed key
    pub verification_ciphertext: String,
}

/// Known verification plaintext (constant, not secret)
const VERIFICATION_PLAINTEXT: &[u8] = b"SecureSharing-Recovery-Verification-v1";

/// Encrypted share for a trustee
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EncryptedTrusteeShare {
    pub trustee_id: String,
    pub trustee_email: String,
    /// Share encrypted with trustee's combined public key (ML-KEM + KAZ-KEM)
    pub encrypted_share: String,
    /// KEM ciphertext for decryption
    pub kem_ciphertext: String,
}

/// Recovery initiation API response
#[derive(Debug, Clone, Serialize, Deserialize)]
struct RecoveryInitiateResponse {
    pub recovery_request: RecoveryRequest,
}

/// Pending recovery request (for trustees to see)
#[derive(Debug, Clone, Serialize, Deserialize)]
struct PendingRecoveryRequest {
    pub id: String,
    pub requester_id: String,
    pub requester_email: String,
    pub requester_name: String,
    pub created_at: String,
    pub expires_at: String,
    /// The trustee's encrypted share
    pub encrypted_share: String,
    /// KEM ciphertext for decryption
    pub kem_ciphertext: String,
}

/// Recovery completion response
#[derive(Debug, Clone, Serialize, Deserialize)]
struct RecoveryCompletionResponse {
    pub success: bool,
    /// Decrypted shares submitted by trustees
    pub shares: Vec<RecoveryShareSubmission>,
    /// Verification ciphertext for validating reconstructed key
    pub verification_ciphertext: String,
}

/// A submitted recovery share
#[derive(Debug, Clone, Serialize, Deserialize)]
struct RecoveryShareSubmission {
    pub trustee_id: String,
    /// Plaintext share data (base64)
    pub share_data: String,
}

impl RecoveryService {
    /// Create a new recovery service
    pub fn new(
        api_client: Arc<ApiClient>,
        crypto_service: Arc<CryptoService>,
        database: Arc<Database>,
    ) -> Self {
        Self {
            api_client,
            crypto_service,
            database,
        }
    }

    /// Setup recovery with trustees
    ///
    /// This splits the master key into shares using Shamir's scheme and
    /// encrypts each share with the corresponding trustee's public key.
    pub async fn setup_recovery(
        &self,
        request: SetupRecoveryRequest,
        master_key: &[u8],
    ) -> AppResult<RecoverySetup> {
        let threshold = request.threshold;
        let num_trustees = request.trustee_emails.len() as u8;

        // Validate parameters
        if threshold < 2 {
            return Err(AppError::Validation(
                "Threshold must be at least 2".to_string(),
            ));
        }
        if num_trustees < threshold as u8 {
            return Err(AppError::Validation(
                "Number of trustees must be >= threshold".to_string(),
            ));
        }
        if num_trustees > 10 {
            return Err(AppError::Validation(
                "Maximum 10 trustees supported".to_string(),
            ));
        }

        // Look up trustee public keys
        let trustees = self.lookup_trustees(&request.trustee_emails).await?;

        // Split master key into shares
        let shares = shamir::split(master_key, threshold as u8, num_trustees)
            .map_err(|e| AppError::Crypto(format!("Shamir split failed: {}", e)))?;

        tracing::debug!(
            "Split master key into {} shares with threshold {}",
            shares.len(),
            threshold
        );

        // Encrypt each share with trustee's public key
        let mut encrypted_shares = Vec::with_capacity(trustees.len());
        for (trustee, share) in trustees.iter().zip(shares.iter()) {
            let encrypted = self.encrypt_share_for_trustee(share, &trustee.public_keys)?;
            encrypted_shares.push(EncryptedTrusteeShare {
                trustee_id: trustee.id.clone(),
                trustee_email: trustee.email.clone(),
                encrypted_share: encrypted.0,
                kem_ciphertext: encrypted.1,
            });
        }

        // Create verification ciphertext (to validate key during recovery)
        let verification_ct = encrypt_aes_gcm(VERIFICATION_PLAINTEXT, master_key)
            .map_err(|e| AppError::Crypto(format!("Verification encryption failed: {}", e)))?;

        // Send to API
        let api_request = RecoverySetupApiRequest {
            threshold,
            encrypted_shares,
            verification_ciphertext: BASE64.encode(&verification_ct),
        };

        let setup: RecoverySetup = self
            .api_client
            .post("/recovery/setup", &api_request)
            .await?;

        tracing::info!("Recovery setup complete with {} trustees", trustees.len());

        Ok(setup)
    }

    /// Get current recovery status
    pub async fn get_recovery_status(&self) -> AppResult<RecoverySetup> {
        self.api_client.get("/recovery/status").await
    }

    /// Initiate account recovery (when user forgets password)
    ///
    /// This starts the recovery process. Trustees will be notified to
    /// approve the request by submitting their shares.
    pub async fn initiate_recovery(
        &self,
        request: InitiateRecoveryRequest,
    ) -> AppResult<RecoveryRequest> {
        // Generate a new encryption salt for the new password
        // The actual key derivation happens in complete_recovery when we
        // re-encrypt the master key with the new password
        let (new_enc_salt, _) = self
            .crypto_service
            .derive_encryption_key_with_salt(&request.new_password)?;

        #[derive(Serialize)]
        struct InitiateRequest {
            email: String,
            new_enc_salt: String,
        }

        let api_request = InitiateRequest {
            email: request.email,
            new_enc_salt,
        };

        let response: RecoveryInitiateResponse = self
            .api_client
            .post("/recovery/initiate", &api_request)
            .await?;

        Ok(response.recovery_request)
    }

    /// Approve a recovery request (called by a trustee)
    ///
    /// This decrypts the trustee's share and submits it to the API.
    pub async fn approve_recovery_request(
        &self,
        recovery_id: &str,
        ml_kem_sk: &str,
        kaz_kem_sk: &str,
    ) -> AppResult<()> {
        // First, get the pending request to retrieve our encrypted share
        let pending: PendingRecoveryRequest = self
            .api_client
            .get(&format!("/recovery/requests/{}", recovery_id))
            .await?;

        // Decrypt our share
        let share_data = self.decrypt_trustee_share(
            &pending.encrypted_share,
            &pending.kem_ciphertext,
            ml_kem_sk,
            kaz_kem_sk,
        )?;

        // Submit the decrypted share
        #[derive(Serialize)]
        struct ApprovalSubmission {
            recovery_id: String,
            share_data: String,
        }

        let submission = ApprovalSubmission {
            recovery_id: recovery_id.to_string(),
            share_data: BASE64.encode(&share_data),
        };

        let _: serde_json::Value = self
            .api_client
            .post("/recovery/approve", &submission)
            .await?;

        tracing::info!("Successfully submitted recovery share for {}", recovery_id);

        Ok(())
    }

    /// Complete recovery process
    ///
    /// This retrieves all submitted shares, reconstructs the master key,
    /// and re-encrypts it with the new password.
    pub async fn complete_recovery(
        &self,
        recovery_id: &str,
        new_password: &str,
    ) -> AppResult<()> {
        // Get all submitted shares
        let completion: RecoveryCompletionResponse = self
            .api_client
            .get(&format!("/recovery/complete/{}", recovery_id))
            .await?;

        if !completion.success {
            return Err(AppError::Validation(
                "Not enough shares submitted yet".to_string(),
            ));
        }

        // Decode shares
        let shares: Result<Vec<Share>, _> = completion
            .shares
            .iter()
            .map(|s| {
                BASE64
                    .decode(&s.share_data)
                    .map_err(|e| AppError::Crypto(format!("Invalid share data: {}", e)))
                    .and_then(|bytes| {
                        Share::from_bytes(&bytes)
                            .map_err(|e| AppError::Crypto(format!("Invalid share format: {}", e)))
                    })
            })
            .collect();
        let shares = shares?;

        // Reconstruct master key
        let master_key = shamir::combine(&shares)
            .map_err(|e| AppError::Crypto(format!("Shamir combine failed: {}", e)))?;

        tracing::info!(
            "Reconstructed master key from {} shares",
            completion.shares.len()
        );

        // Verify master key is valid (32 bytes)
        if master_key.len() != KEY_SIZE {
            return Err(AppError::Crypto(
                "Reconstructed key has invalid size".to_string(),
            ));
        }

        // Cryptographically verify the reconstructed key is correct
        // by decrypting the verification ciphertext
        let verification_ct = BASE64
            .decode(&completion.verification_ciphertext)
            .map_err(|e| AppError::Crypto(format!("Invalid verification ciphertext: {}", e)))?;

        let decrypted_verification = decrypt_aes_gcm(&verification_ct, &master_key)
            .map_err(|_| AppError::Crypto(
                "Key verification failed. The reconstructed key is incorrect. \
                This may indicate corrupted or mismatched shares from trustees.".to_string()
            ))?;

        // Verify the decrypted value matches our known plaintext
        if decrypted_verification.as_slice() != VERIFICATION_PLAINTEXT {
            return Err(AppError::Crypto(
                "Key verification failed. The reconstructed key does not match. \
                Please ensure all trustees submitted correct shares.".to_string()
            ));
        }

        tracing::info!("Reconstructed key verified successfully");

        // Derive new encryption key
        let (new_enc_salt, new_enc_key) = self
            .crypto_service
            .derive_encryption_key_with_salt(new_password)?;

        // Encrypt master key with new password
        let (encrypted_mk, mk_nonce) = self
            .crypto_service
            .encrypt_master_key(&master_key, &new_enc_key)?;

        // Generate new key pairs (old ones are compromised)
        let (ml_kem_pk, ml_kem_sk) = self.crypto_service.generate_ml_kem_keypair()?;
        let (ml_dsa_pk, ml_dsa_sk) = self.crypto_service.generate_ml_dsa_keypair()?;
        let (kaz_kem_pk, kaz_kem_sk) = self.crypto_service.generate_kaz_kem_keypair()?;
        let (kaz_sign_pk, kaz_sign_sk) = self.crypto_service.generate_kaz_sign_keypair()?;

        // Encrypt private keys with master key
        let encrypted_ml_kem_sk = self
            .crypto_service
            .encrypt_private_key(&ml_kem_sk, &master_key)?;
        let encrypted_ml_dsa_sk = self
            .crypto_service
            .encrypt_private_key(&ml_dsa_sk, &master_key)?;
        let encrypted_kaz_kem_sk = self
            .crypto_service
            .encrypt_private_key(&kaz_kem_sk, &master_key)?;
        let encrypted_kaz_sign_sk = self
            .crypto_service
            .encrypt_private_key(&kaz_sign_sk, &master_key)?;

        // Derive new auth key for login
        let (auth_salt, _auth_key) = self.crypto_service.derive_auth_key(new_password)?;

        // Submit new key bundle to API
        #[derive(Serialize)]
        struct NewKeyBundle {
            recovery_id: String,
            encrypted_master_key: String,
            mk_nonce: String,
            encrypted_ml_kem_sk: String,
            encrypted_ml_dsa_sk: String,
            encrypted_kaz_kem_sk: String,
            encrypted_kaz_sign_sk: String,
            ml_kem_pk: String,
            ml_dsa_pk: String,
            kaz_kem_pk: String,
            kaz_sign_pk: String,
            auth_salt: String,
            enc_salt: String,
        }

        let key_bundle = NewKeyBundle {
            recovery_id: recovery_id.to_string(),
            encrypted_master_key: encrypted_mk,
            mk_nonce,
            encrypted_ml_kem_sk,
            encrypted_ml_dsa_sk,
            encrypted_kaz_kem_sk,
            encrypted_kaz_sign_sk,
            ml_kem_pk,
            ml_dsa_pk,
            kaz_kem_pk,
            kaz_sign_pk,
            auth_salt,
            enc_salt: new_enc_salt,
        };

        let _: serde_json::Value = self
            .api_client
            .post("/recovery/finalize", &key_bundle)
            .await?;

        // Set the new master key in the crypto service
        self.crypto_service.set_master_key(master_key)?;

        tracing::info!("Recovery complete, new key bundle uploaded");

        Ok(())
    }

    /// Get pending recovery requests where this user is a trustee
    pub async fn get_pending_requests(&self) -> AppResult<Vec<RecoveryRequest>> {
        self.api_client.get("/recovery/pending").await
    }

    // ==================== Private helpers ====================

    /// Look up trustees by email
    async fn lookup_trustees(&self, emails: &[String]) -> AppResult<Vec<TrusteeLookup>> {
        #[derive(Serialize)]
        struct LookupRequest {
            emails: Vec<String>,
        }

        let request = LookupRequest {
            emails: emails.to_vec(),
        };

        let trustees: Vec<TrusteeLookup> = self
            .api_client
            .post("/users/lookup", &request)
            .await?;

        // Verify all trustees were found
        if trustees.len() != emails.len() {
            let found_emails: std::collections::HashSet<_> =
                trustees.iter().map(|t| t.email.as_str()).collect();
            let missing: Vec<&str> = emails
                .iter()
                .filter(|e| !found_emails.contains(e.as_str()))
                .map(|e| e.as_str())
                .collect();
            return Err(AppError::Validation(format!(
                "Trustees not found: {}",
                missing.join(", ")
            )));
        }

        Ok(trustees)
    }

    /// Encrypt a share for a trustee using their public keys
    fn encrypt_share_for_trustee(
        &self,
        share: &Share,
        public_keys: &RecipientPublicKeys,
    ) -> AppResult<(String, String)> {
        // Encapsulate shared secret using trustee's public keys
        let (kem_ciphertext, shared_secret) = self
            .crypto_service
            .encapsulate(&public_keys.ml_kem_pk, &public_keys.kaz_kem_pk)?;

        // Encrypt share with derived key
        let share_bytes = share.to_bytes();
        let encrypted = encrypt_aes_gcm(&share_bytes, &shared_secret)
            .map_err(|e| AppError::Crypto(format!("Share encryption failed: {}", e)))?;

        Ok((BASE64.encode(&encrypted), kem_ciphertext))
    }

    /// Decrypt a trustee share using private keys
    fn decrypt_trustee_share(
        &self,
        encrypted_share_b64: &str,
        kem_ciphertext_b64: &str,
        ml_kem_sk_b64: &str,
        kaz_kem_sk_b64: &str,
    ) -> AppResult<Vec<u8>> {
        // Decapsulate to get shared secret
        let shared_secret = self.crypto_service.decapsulate(
            kem_ciphertext_b64,
            ml_kem_sk_b64,
            kaz_kem_sk_b64,
        )?;

        // Decrypt the share
        let encrypted = BASE64
            .decode(encrypted_share_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid encrypted share: {}", e)))?;

        let share_bytes = decrypt_aes_gcm(&encrypted, &shared_secret)
            .map_err(|e| AppError::Crypto(format!("Share decryption failed: {}", e)))?;

        Ok(share_bytes)
    }
}
