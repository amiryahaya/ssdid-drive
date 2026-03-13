//! Recovery key management service
//!
//! Implements Shamir's Secret Sharing for key recovery using the `sharks` crate.
//! Users split their master key into shares; a threshold of shares is required
//! to reconstruct the key.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sharks::{Share, Sharks};
use std::sync::Arc;
use zeroize::Zeroize;

use crate::error::{AppError, AppResult};
use crate::services::ApiClient;

/// A recovery file exported for a single share
#[derive(Debug, Serialize, Deserialize)]
pub struct RecoveryFile {
    pub version: u32,
    pub scheme: String,
    pub threshold: u32,
    pub share_index: u8,
    pub share_data: String,
    pub checksum: String,
    pub user_did: String,
    pub created_at: String,
}

/// Current recovery setup status
#[derive(Debug, Serialize, Deserialize)]
pub struct RecoveryStatus {
    pub is_active: bool,
    pub created_at: Option<String>,
}

/// Response from server-side share retrieval
#[derive(Debug, Serialize, Deserialize)]
pub struct ServerShareResponse {
    pub server_share: String,
    pub share_index: u8,
}

/// Response from recovery completion
#[derive(Debug, Serialize, Deserialize)]
pub struct CompleteRecoveryResponse {
    pub token: String,
    pub user_id: String,
}

/// Recovery service using Shamir's Secret Sharing (sharks crate, GF(2^8))
pub struct RecoveryService {
    api_client: Arc<ApiClient>,
}

impl RecoveryService {
    /// Create a new recovery service
    pub fn new(api_client: Arc<ApiClient>) -> Self {
        Self { api_client }
    }

    /// Split a 32-byte master key into 3 Shamir shares (threshold 2).
    ///
    /// Returns `((index1, data1), (index2, data2), (index3, data3))`.
    /// The sharks crate encodes each share as `[x, y[0], y[1], ...]`.
    /// We separate `x` (the share index) from the `y` data bytes.
    pub fn split_master_key(
        master_key: &[u8; 32],
    ) -> AppResult<((u8, Vec<u8>), (u8, Vec<u8>), (u8, Vec<u8>))> {
        let sharks = Sharks(2);
        let dealer = sharks.dealer(master_key);
        let shares: Vec<Share> = dealer.take(3).collect();

        if shares.len() != 3 {
            return Err(AppError::Crypto("Failed to generate 3 Shamir shares".to_string()));
        }

        let extract = |s: &Share| -> (u8, Vec<u8>) {
            // Vec::from(&share) gives [x, y[0], y[1], ...]
            let mut bytes = Vec::from(s);
            let index = bytes[0];
            let data = bytes[1..].to_vec();
            bytes.zeroize();
            (index, data)
        };

        Ok((extract(&shares[0]), extract(&shares[1]), extract(&shares[2])))
    }

    /// Reconstruct a 32-byte master key from 2 Shamir shares.
    ///
    /// Each share is specified as `(index, data)` where `index` is the
    /// x-coordinate and `data` is the y-bytes, as produced by `split_master_key`.
    pub fn reconstruct_master_key(
        index1: u8,
        data1: &[u8],
        index2: u8,
        data2: &[u8],
    ) -> AppResult<[u8; 32]> {
        if index1 == index2 {
            return Err(AppError::Crypto("Duplicate share indices".to_string()));
        }

        // Reconstruct full share bytes: [x, y[0], y[1], ...]
        let mut s1_bytes = vec![index1];
        s1_bytes.extend_from_slice(data1);
        let mut s2_bytes = vec![index2];
        s2_bytes.extend_from_slice(data2);

        let s1 = Share::try_from(s1_bytes.as_slice())
            .map_err(|e| AppError::Crypto(format!("Invalid share 1: {}", e)))?;
        let s2 = Share::try_from(s2_bytes.as_slice())
            .map_err(|e| AppError::Crypto(format!("Invalid share 2: {}", e)))?;

        // Zeroize intermediate buffers
        s1_bytes.zeroize();
        s2_bytes.zeroize();

        let sharks = Sharks(2);
        let mut secret = sharks
            .recover(&[s1, s2])
            .map_err(|e| AppError::Crypto(format!("Reconstruction failed: {}", e)))?;

        if secret.len() != 32 {
            secret.zeroize();
            return Err(AppError::Crypto(format!(
                "Reconstructed key is {} bytes, expected 32",
                secret.len()
            )));
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&secret);
        secret.zeroize();
        Ok(key)
    }

    /// Create a `RecoveryFile` struct for export as JSON.
    ///
    /// The `share_data` is base64-encoded; `checksum` is the SHA-256 hex
    /// digest of the raw share bytes for integrity verification.
    pub fn create_recovery_file(
        share_index: u8,
        share_data: &[u8],
        user_did: &str,
    ) -> RecoveryFile {
        let checksum = hex::encode(Sha256::digest(share_data));
        RecoveryFile {
            version: 1,
            scheme: "shamir-gf256".to_string(),
            threshold: 2,
            share_index,
            share_data: BASE64.encode(share_data),
            checksum,
            user_did: user_did.to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Parse and validate a `.recovery` JSON file.
    ///
    /// Verifies the version field and SHA-256 checksum of the share data.
    pub fn parse_recovery_file(contents: &str) -> AppResult<RecoveryFile> {
        let file: RecoveryFile = serde_json::from_str(contents)
            .map_err(|e| AppError::Crypto(format!("Invalid recovery file: {}", e)))?;

        if file.version != 1 {
            return Err(AppError::Validation(
                "This recovery file requires a newer version of SSDID Drive".to_string(),
            ));
        }

        let raw_bytes = BASE64
            .decode(&file.share_data)
            .map_err(|e| AppError::Crypto(format!("Invalid share_data base64: {}", e)))?;

        let expected_checksum = hex::encode(Sha256::digest(&raw_bytes));
        if file.checksum != expected_checksum {
            return Err(AppError::Crypto(
                "Recovery file is damaged (checksum mismatch)".to_string(),
            ));
        }

        Ok(file)
    }

    /// Compute key_proof: SHA-256 hex digest of the KEM public key.
    pub fn compute_key_proof(kem_public_key: &[u8]) -> String {
        hex::encode(Sha256::digest(kem_public_key))
    }

    // --- API calls ---

    /// Upload the server's share and key proof to the recovery setup endpoint.
    pub async fn setup(&self, server_share: &str, key_proof: &str) -> AppResult<()> {
        self.api_client
            .post::<_, serde_json::Value>(
                "/api/recovery/setup",
                &serde_json::json!({
                    "server_share": server_share,
                    "key_proof": key_proof
                }),
            )
            .await?;
        Ok(())
    }

    /// Retrieve current recovery setup status from the server.
    pub async fn get_status(&self) -> AppResult<RecoveryStatus> {
        self.api_client.get("/api/recovery/status").await
    }

    /// Retrieve the server-held share for a given DID (used during recovery).
    pub async fn get_server_share(&self, did: &str) -> AppResult<ServerShareResponse> {
        let url = format!("/api/recovery/share?did={}", urlencoding::encode(did));
        self.api_client.get(&url).await
    }

    /// Complete the recovery process with a new DID and key material.
    pub async fn complete_recovery(
        &self,
        old_did: &str,
        new_did: &str,
        key_proof: &str,
        kem_public_key: &str,
    ) -> AppResult<CompleteRecoveryResponse> {
        self.api_client
            .post(
                "/api/recovery/complete",
                &serde_json::json!({
                    "old_did": old_did,
                    "new_did": new_did,
                    "key_proof": key_proof,
                    "kem_public_key": kem_public_key
                }),
            )
            .await
    }

    /// Delete the current recovery setup from the server.
    pub async fn delete_setup(&self) -> AppResult<()> {
        self.api_client
            .delete::<serde_json::Value>("/api/recovery/setup")
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_and_reconstruct_master_key() {
        let master_key = [0x42u8; 32];

        let ((i1, d1), (i2, d2), (i3, d3)) =
            RecoveryService::split_master_key(&master_key).unwrap();

        // Reconstruct from shares 1 and 2
        let reconstructed = RecoveryService::reconstruct_master_key(i1, &d1, i2, &d2).unwrap();
        assert_eq!(reconstructed, master_key);

        // Reconstruct from shares 1 and 3
        let reconstructed = RecoveryService::reconstruct_master_key(i1, &d1, i3, &d3).unwrap();
        assert_eq!(reconstructed, master_key);

        // Reconstruct from shares 2 and 3
        let reconstructed = RecoveryService::reconstruct_master_key(i2, &d2, i3, &d3).unwrap();
        assert_eq!(reconstructed, master_key);
    }

    #[test]
    fn test_create_and_parse_recovery_file() {
        let share_data = vec![0xABu8; 33]; // 33 bytes: 1 index + 32 y-bytes
        let file = RecoveryService::create_recovery_file(1, &share_data, "did:ssdid:test123");

        assert_eq!(file.version, 1);
        assert_eq!(file.scheme, "shamir-gf256");
        assert_eq!(file.threshold, 2);
        assert_eq!(file.share_index, 1);
        assert_eq!(file.user_did, "did:ssdid:test123");

        // Round-trip: serialize and parse
        let json = serde_json::to_string(&file).unwrap();
        let parsed = RecoveryService::parse_recovery_file(&json).unwrap();

        assert_eq!(parsed.share_index, 1);
        assert_eq!(parsed.user_did, "did:ssdid:test123");
        assert_eq!(parsed.checksum, file.checksum);
    }

    #[test]
    fn test_parse_recovery_file_bad_checksum() {
        let share_data = vec![0x01u8; 33];
        let mut file = RecoveryService::create_recovery_file(1, &share_data, "did:ssdid:test");
        // Corrupt the checksum
        file.checksum = "deadbeef".to_string();

        let json = serde_json::to_string(&file).unwrap();
        let result = RecoveryService::parse_recovery_file(&json);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.to_string().contains("checksum"));
    }

    #[test]
    fn test_parse_recovery_file_unsupported_version() {
        let share_data = vec![0x01u8; 33];
        let mut file = RecoveryService::create_recovery_file(1, &share_data, "did:ssdid:test");
        file.version = 2;
        // Recompute checksum so it passes that check
        file.checksum = hex::encode(Sha256::digest(&share_data));

        let json = serde_json::to_string(&file).unwrap();
        let result = RecoveryService::parse_recovery_file(&json);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.to_string().contains("newer version"));
    }

    #[test]
    fn test_compute_key_proof() {
        let pk = b"test_public_key_bytes";
        let proof = RecoveryService::compute_key_proof(pk);
        // Should be a 64-char hex string (SHA-256 = 32 bytes = 64 hex chars)
        assert_eq!(proof.len(), 64);
        // Deterministic
        assert_eq!(RecoveryService::compute_key_proof(pk), proof);
    }

    #[test]
    fn test_share_indices_are_distinct() {
        let master_key = [0x11u8; 32];
        let ((i1, _), (i2, _), (i3, _)) =
            RecoveryService::split_master_key(&master_key).unwrap();
        assert_ne!(i1, i2);
        assert_ne!(i1, i3);
        assert_ne!(i2, i3);
    }
}
