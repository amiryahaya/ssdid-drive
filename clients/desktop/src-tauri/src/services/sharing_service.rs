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
use zeroize::Zeroize;

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

    /// Create a share for a file or folder
    pub async fn create_share(
        &self,
        request: CreateShareRequest,
        signing_keys: Option<(&str, &str)>, // (ml_dsa_sk, kaz_sign_sk) for signing
    ) -> AppResult<CreateShareResponse> {
        // Step 1: Get recipient's public keys
        let recipient_keys = self.get_recipient_keys(&request.recipient_email).await?;

        // Step 2: Get the item's encrypted DEK from API
        #[derive(serde::Deserialize)]
        struct ItemKeyInfo {
            encrypted_dek: String,
            folder_id: Option<String>,
        }

        let item_info: ItemKeyInfo = self
            .api_client
            .get(&format!("/files/{}/key", request.item_id))
            .await?;

        // Step 3: Decrypt the item's DEK using the folder KEK
        let folder_id = item_info.folder_id.unwrap_or_else(|| "root".to_string());
        let mut kek = self.crypto_service.derive_folder_kek(&folder_id)?;
        let mut dek = self.crypto_service.decrypt_dek(&item_info.encrypted_dek, &kek)?;

        // Zeroize KEK immediately after decrypting DEK
        kek.zeroize();

        // Step 4: Encrypt the DEK for the recipient using combined KEM
        let (encrypted_share_key, mut shared_secret) = self.crypto_service.encapsulate(
            &recipient_keys.ml_kem_pk,
            &recipient_keys.kaz_kem_pk,
        )?;

        // Use the shared secret to encrypt the DEK
        let encrypted_dek_for_recipient = self
            .crypto_service
            .encrypt_file_chunk(&dek, &shared_secret)?;
        let encrypted_dek_b64 = BASE64.encode(&encrypted_dek_for_recipient);

        // Zeroize DEK and shared secret immediately after use
        dek.zeroize();
        shared_secret.zeroize();

        // Step 5: Create signature of the share grant (required for authenticity)
        let (ml_dsa_sk, kaz_sign_sk) = signing_keys.ok_or_else(|| {
            AppError::Auth(
                "Signing keys required to create a share. Please ensure you are logged in.".to_string()
            )
        })?;

        // Create a canonical share grant message
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
        let signature = sig_result.signature;

        // Step 6: Send share to API
        #[derive(serde::Serialize)]
        struct ApiCreateShareRequest {
            item_id: String,
            recipient_email: String,
            permission: String,
            expires_at: Option<String>,
            message: Option<String>,
            encrypted_share_key: String,
            encrypted_dek: String,
            signature: String,
        }

        let api_request = ApiCreateShareRequest {
            item_id: request.item_id,
            recipient_email: request.recipient_email,
            permission: permission_to_string(&request.permission),
            expires_at: request.expires_at,
            message: request.message,
            encrypted_share_key,
            encrypted_dek: encrypted_dek_b64,
            signature,
        };

        let response: CreateShareResponse = self
            .api_client
            .post("/shares", &api_request)
            .await?;

        tracing::info!("Share created successfully: {}", response.share.id);
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

    /// Decrypt a shared item's DEK using the user's private keys
    pub async fn decrypt_share_key(
        &self,
        encrypted_share_key: &str,
        encrypted_dek: &str,
        ml_kem_sk: &str,
        kaz_kem_sk: &str,
    ) -> AppResult<Vec<u8>> {
        // Decapsulate to get the shared secret
        let mut shared_secret = self.crypto_service.decapsulate(
            encrypted_share_key,
            ml_kem_sk,
            kaz_kem_sk,
        )?;

        // Decrypt the DEK using the shared secret
        let encrypted_dek_bytes = BASE64
            .decode(encrypted_dek)
            .map_err(|e| AppError::Crypto(format!("Invalid encrypted DEK: {}", e)))?;

        let dek = self
            .crypto_service
            .decrypt_file_chunk(&encrypted_dek_bytes, &shared_secret)?;

        // Zeroize shared secret after use
        shared_secret.zeroize();

        Ok(dek)
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
