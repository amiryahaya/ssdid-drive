//! File sharing service

use crate::error::{AppError, AppResult};
use crate::models::{
    CreateShareRequest, CreateShareResponse, RecipientPublicKeys, RecipientSearchResult, Share,
    ShareListResponse, SharePermission,
};
use crate::services::{ApiClient, CryptoService};
use crate::storage::Database;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use std::sync::Arc;
use zeroize::{Zeroize, Zeroizing};

/// Service for file sharing operations
pub struct SharingService {
    api_client: Arc<ApiClient>,
    crypto_service: Arc<CryptoService>,
    database: Arc<Database>,
}

impl SharingService {
    /// Create a new sharing service
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

    /// Search for users to share with
    pub async fn search_recipients(&self, query: &str) -> AppResult<Vec<RecipientSearchResult>> {
        #[derive(serde::Deserialize)]
        struct SearchResponse {
            users: Vec<RecipientSearchResult>,
        }

        let response: SearchResponse = self
            .api_client
            .get(&format!("/users/search?q={}", urlencoding::encode(query)))
            .await?;

        Ok(response.users)
    }

    /// Get a recipient's public keys by email
    pub async fn get_recipient_keys(&self, email: &str) -> AppResult<RecipientPublicKeys> {
        #[derive(serde::Deserialize)]
        struct KeysResponse {
            public_keys: RecipientPublicKeys,
        }

        let response: KeysResponse = self
            .api_client
            .get(&format!(
                "/users/keys?email={}",
                urlencoding::encode(email)
            ))
            .await?;

        Ok(response.public_keys)
    }

    /// Create a share for a file or folder.
    ///
    /// For folder sharing: re-encapsulates the folder key with the recipient's
    /// public KEM keys so they can decrypt all files in the folder.
    pub async fn create_share(
        &self,
        request: CreateShareRequest,
        signing_keys: Option<(&str, &str)>, // (ml_dsa_sk, kaz_sign_sk) for signing
    ) -> AppResult<CreateShareResponse> {
        // Step 1: Get recipient's public keys
        let recipient_keys = self.get_recipient_keys(&request.recipient_email).await?;

        // Step 2: Get the folder's KEM-encrypted folder key from API
        #[derive(serde::Deserialize)]
        struct FolderKeyResponse {
            encrypted_folder_key: String,
            wrapped_folder_key: String,
            kem_algorithm: String,
            folder_id: String,
        }

        let folder_info: FolderKeyResponse = self
            .api_client
            .get(&format!("/files/{}/folder-key", request.item_id))
            .await?;

        // Step 3: Get owner's private KEM keys to decrypt the folder key
        let master_key = self.crypto_service.get_master_key()?;

        let encrypted_ml_kem_sk = self
            .database
            .get_setting("encrypted_ml_kem_sk")?
            .ok_or_else(|| AppError::Crypto("ML-KEM private key not found".to_string()))?;
        let encrypted_kaz_kem_sk = self
            .database
            .get_setting("encrypted_kaz_kem_sk")?
            .ok_or_else(|| AppError::Crypto("KAZ-KEM private key not found".to_string()))?;

        let ml_kem_sk = self
            .crypto_service
            .decrypt_private_key(&encrypted_ml_kem_sk, &master_key)?;
        let kaz_kem_sk = self
            .crypto_service
            .decrypt_private_key(&encrypted_kaz_kem_sk, &master_key)?;

        let mut ml_kem_sk_b64 = BASE64.encode(&*ml_kem_sk);
        let mut kaz_kem_sk_b64 = BASE64.encode(&*kaz_kem_sk);

        // Step 4: Re-encapsulate folder key for recipient
        let re_encap_result = self
            .crypto_service
            .re_encapsulate_folder_key(
                &folder_info.encrypted_folder_key,
                &folder_info.wrapped_folder_key,
                &ml_kem_sk_b64,
                &kaz_kem_sk_b64,
                &recipient_keys.ml_kem_pk,
                &recipient_keys.kaz_kem_pk,
            );
        ml_kem_sk_b64.zeroize();
        kaz_kem_sk_b64.zeroize();
        let (encrypted_share_key, encrypted_folder_key_for_recipient, kem_algorithm) =
            re_encap_result?;

        // Step 5: Create signature of the share grant (required for authenticity)
        let signature = if let Some((ml_dsa_sk, kaz_sign_sk)) = signing_keys {
            let grant_message = format!(
                "share:{}:{}:{}:{}",
                request.item_id,
                request.recipient_email,
                permission_to_string(&request.permission),
                request.expires_at.as_deref().unwrap_or("none")
            );

            let sig_result = self.crypto_service.sign_with_key(
                grant_message.as_bytes(),
                ml_dsa_sk,
                kaz_sign_sk,
            )?;
            sig_result.signature
        } else {
            // In SSDID model, signing may be handled by wallet
            String::new()
        };

        // Step 6: Send share to API
        #[derive(serde::Serialize)]
        struct ApiCreateShareRequest {
            item_id: String,
            recipient_email: String,
            permission: String,
            expires_at: Option<String>,
            message: Option<String>,
            encrypted_share_key: String,
            encrypted_folder_key: String,
            kem_algorithm: String,
            signature: String,
        }

        let api_request = ApiCreateShareRequest {
            item_id: request.item_id,
            recipient_email: request.recipient_email,
            permission: permission_to_string(&request.permission),
            expires_at: request.expires_at,
            message: request.message,
            encrypted_share_key,
            encrypted_folder_key: encrypted_folder_key_for_recipient,
            kem_algorithm,
            signature,
        };

        let response: CreateShareResponse = self
            .api_client
            .post("/shares", &api_request)
            .await?;

        tracing::info!("Share created with KEM re-encapsulation: {}", response.share.id);
        Ok(response)
    }

    /// Revoke an existing share
    pub async fn revoke_share(&self, share_id: &str) -> AppResult<()> {
        self.api_client
            .delete_no_content(&format!("/shares/{}", share_id))
            .await?;

        tracing::info!("Share revoked: {}", share_id);
        Ok(())
    }

    /// Update share permissions
    pub async fn update_share(
        &self,
        share_id: &str,
        permission: SharePermission,
        expires_at: Option<String>,
    ) -> AppResult<Share> {
        #[derive(serde::Serialize)]
        struct UpdateShareRequest {
            permission: String,
            expires_at: Option<String>,
        }

        let request = UpdateShareRequest {
            permission: permission_to_string(&permission),
            expires_at,
        };

        let share: Share = self
            .api_client
            .put(&format!("/shares/{}", share_id), &request)
            .await?;

        tracing::info!("Share updated: {}", share_id);
        Ok(share)
    }

    /// List shares created by the current user
    pub async fn list_my_shares(&self) -> AppResult<ShareListResponse> {
        let response: ShareListResponse = self.api_client.get("/shares/outgoing").await?;
        Ok(response)
    }

    /// List shares received by the current user
    pub async fn list_shared_with_me(&self) -> AppResult<ShareListResponse> {
        let response: ShareListResponse = self.api_client.get("/shares/incoming").await?;
        Ok(response)
    }

    /// Get details for a specific share
    pub async fn get_share_details(&self, share_id: &str) -> AppResult<Share> {
        let share: Share = self
            .api_client
            .get(&format!("/shares/{}", share_id))
            .await?;
        Ok(share)
    }

    /// Accept a received share
    pub async fn accept_share(&self, share_id: &str) -> AppResult<Share> {
        #[derive(serde::Serialize)]
        struct AcceptRequest {
            action: String,
        }

        let request = AcceptRequest {
            action: "accept".to_string(),
        };

        let share: Share = self
            .api_client
            .post(&format!("/shares/{}/respond", share_id), &request)
            .await?;

        tracing::info!("Share accepted: {}", share_id);
        Ok(share)
    }

    /// Decline a received share
    pub async fn decline_share(&self, share_id: &str) -> AppResult<()> {
        #[derive(serde::Serialize)]
        struct DeclineRequest {
            action: String,
        }

        let request = DeclineRequest {
            action: "decline".to_string(),
        };

        let _: serde_json::Value = self
            .api_client
            .post(&format!("/shares/{}/respond", share_id), &request)
            .await?;

        tracing::info!("Share declined: {}", share_id);
        Ok(())
    }

    /// Decrypt a shared folder key using the user's private KEM keys.
    ///
    /// The share contains:
    /// - `encrypted_share_key`: KEM ciphertext (base64)
    /// - `encrypted_folder_key`: AES-wrapped folder key (base64)
    ///
    /// Returns the plaintext folder key.
    pub async fn decrypt_share_folder_key(
        &self,
        encrypted_share_key: &str,
        encrypted_folder_key: &str,
        ml_kem_sk: &str,
        kaz_kem_sk: &str,
    ) -> AppResult<Zeroizing<Vec<u8>>> {
        // Decapsulate KEM to get shared secret, then unwrap folder key
        let folder_key = self.crypto_service.decapsulate_folder_key(
            encrypted_share_key,
            encrypted_folder_key,
            ml_kem_sk,
            kaz_kem_sk,
        )?;

        Ok(folder_key)
    }
}

/// Convert SharePermission to API string
fn permission_to_string(permission: &SharePermission) -> String {
    match permission {
        SharePermission::Read => "read".to_string(),
        SharePermission::Write => "write".to_string(),
        SharePermission::Admin => "admin".to_string(),
    }
}
