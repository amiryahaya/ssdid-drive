//! PII Service client for conversation-based PII detection and token management
//!
//! This module handles communication with the PII microservice for:
//! - Creating and managing conversations
//! - Registering KEM public keys for post-quantum DEK encryption
//! - Sending messages and receiving tokenized responses
//! - Unwrapping KEM-encrypted DEKs and decrypting token maps

use crate::error::{AppError, AppResult};
use crate::services::crypto_service::CryptoService;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use parking_lot::RwLock;
use reqwest::{header, Client};
use ssdid_drive_crypto::{
    ml_kem,
    symmetric::{decrypt_aes_gcm, hkdf_derive, KEY_SIZE},
};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

/// Default PII service URL
const DEFAULT_PII_SERVICE_URL: &str = "http://localhost:4001/api/v1";

/// Environment variable for PII service URL override
const PII_SERVICE_URL_ENV_VAR: &str = "PII_SERVICE_URL";

/// Get PII service base URL
fn get_pii_service_url() -> String {
    std::env::var(PII_SERVICE_URL_ENV_VAR).unwrap_or_else(|_| DEFAULT_PII_SERVICE_URL.to_string())
}

// ═══════════════════════════════════════════════════════════════════════════
// API TYPES
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Serialize)]
pub struct CreateConversationRequest {
    pub title: Option<String>,
    pub llm_provider: String,
    pub llm_model: String,
}

#[derive(Debug, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub title: Option<String>,
    pub status: String,
    pub llm_provider: String,
    pub llm_model: String,
    pub created_at: String,
    pub ml_kem_public_key: Option<String>,
    pub kaz_kem_public_key: Option<String>,
    pub kem_keys_registered_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RegisterKemKeysRequest {
    pub ml_kem_public_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kaz_kem_public_key: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RegisterKemKeysResponse {
    pub success: bool,
    pub kem_keys_registered_at: String,
}

#[derive(Debug, Serialize)]
pub struct AskRequest {
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context_files: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_key: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AskResponse {
    pub user_message_id: String,
    pub assistant_message_id: String,
    pub content: String,
    pub role: String,
    pub tokens_detected: i32,
    pub llm_tokens_used: i32,
    pub created_at: String,
    /// Encrypted token map (base64)
    pub encrypted_token_map: String,
    /// Session key (DEK) - base64 (only if no KEM keys registered)
    pub session_key: Option<String>,
    /// Token map version
    pub token_map_version: i32,
    /// KEM-wrapped DEK (base64, present if KEM keys registered)
    pub wrapped_dek: Option<String>,
    /// ML-KEM ciphertext (base64, present if KEM keys registered)
    pub ml_kem_ciphertext: Option<String>,
    /// KAZ-KEM ciphertext (base64, present if KAZ-KEM was used)
    pub kaz_kem_ciphertext: Option<String>,
}

/// Decrypted response with restored PII
#[derive(Debug, Clone, Serialize)]
pub struct DecryptedAskResponse {
    pub user_message_id: String,
    pub assistant_message_id: String,
    /// Original content with PII restored
    pub content: String,
    /// Tokenized content (with PII replaced by tokens)
    pub tokenized_content: String,
    pub role: String,
    pub tokens_detected: i32,
    pub created_at: String,
}

// ═══════════════════════════════════════════════════════════════════════════
// PII SERVICE CLIENT
// ═══════════════════════════════════════════════════════════════════════════

/// Client for PII service API
pub struct PiiServiceClient {
    client: Client,
    base_url: String,
    auth_token: RwLock<Option<String>>,
    /// Current ML-KEM secret key for this session (zeroized on drop)
    ml_kem_secret_key: RwLock<Option<Vec<u8>>>,
    /// Current KAZ-KEM secret key for this session (zeroized on drop)
    kaz_kem_secret_key: RwLock<Option<Vec<u8>>>,
}

impl PiiServiceClient {
    /// Create a new PII service client
    pub fn new() -> AppResult<Self> {
        let client = Client::builder()
            .user_agent("SsdidDrive-Desktop")
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .map_err(|e| AppError::Network(e.to_string()))?;

        let base_url = get_pii_service_url();
        tracing::info!("PII service client initialized with URL: {}", base_url);

        Ok(Self {
            client,
            base_url,
            auth_token: RwLock::new(None),
            ml_kem_secret_key: RwLock::new(None),
            kaz_kem_secret_key: RwLock::new(None),
        })
    }

    /// Set authentication token
    pub fn set_auth_token(&self, token: Option<String>) {
        *self.auth_token.write() = token;
    }

    /// Store KEM secret keys for DEK unwrapping
    pub fn set_kem_secret_keys(&self, ml_kem_sk: Vec<u8>, kaz_kem_sk: Option<Vec<u8>>) {
        *self.ml_kem_secret_key.write() = Some(ml_kem_sk);
        *self.kaz_kem_secret_key.write() = kaz_kem_sk;
    }

    /// Clear KEM secret keys
    pub fn clear_kem_secret_keys(&self) {
        if let Some(mut key) = self.ml_kem_secret_key.write().take() {
            key.iter_mut().for_each(|b| *b = 0);
        }
        if let Some(mut key) = self.kaz_kem_secret_key.write().take() {
            key.iter_mut().for_each(|b| *b = 0);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONVERSATION API
    // ═══════════════════════════════════════════════════════════════════════════

    /// Create a new conversation
    pub async fn create_conversation(
        &self,
        request: CreateConversationRequest,
    ) -> AppResult<Conversation> {
        let response = self
            .post("/conversations", &request)
            .await?;
        Ok(response)
    }

    /// Get a conversation by ID
    pub async fn get_conversation(&self, conversation_id: &str) -> AppResult<Conversation> {
        self.get(&format!("/conversations/{}", conversation_id)).await
    }

    /// List conversations
    pub async fn list_conversations(&self) -> AppResult<Vec<Conversation>> {
        #[derive(Deserialize)]
        struct ListResponse {
            conversations: Vec<Conversation>,
        }
        let response: ListResponse = self.get("/conversations").await?;
        Ok(response.conversations)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // KEM KEY REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Generate and register KEM keys for a conversation
    ///
    /// This generates new ML-KEM (and optionally KAZ-KEM) keypairs,
    /// registers the public keys with the PII service, and stores
    /// the secret keys locally for DEK unwrapping.
    pub async fn register_kem_keys(
        &self,
        conversation_id: &str,
        crypto_service: &CryptoService,
        include_kaz_kem: bool,
    ) -> AppResult<RegisterKemKeysResponse> {
        // Generate ML-KEM keypair
        let (ml_kem_pk_b64, ml_kem_sk_b64) = crypto_service.generate_ml_kem_keypair()?;

        // Optionally generate KAZ-KEM keypair
        let (kaz_kem_pk_b64, kaz_kem_sk) = if include_kaz_kem {
            let (pk, sk) = crypto_service.generate_kaz_kem_keypair()?;
            let sk_bytes = BASE64
                .decode(&sk)
                .map_err(|e| AppError::Crypto(format!("Invalid KAZ-KEM key: {}", e)))?;
            (Some(pk), Some(sk_bytes))
        } else {
            (None, None)
        };

        // Register public keys with PII service
        let request = RegisterKemKeysRequest {
            ml_kem_public_key: ml_kem_pk_b64,
            kaz_kem_public_key: kaz_kem_pk_b64,
        };

        let response: RegisterKemKeysResponse = self
            .post(&format!("/conversations/{}/keys", conversation_id), &request)
            .await?;

        // Store secret keys for DEK unwrapping
        let ml_kem_sk = BASE64
            .decode(&ml_kem_sk_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-KEM key: {}", e)))?;

        self.set_kem_secret_keys(ml_kem_sk, kaz_kem_sk);

        tracing::info!(
            "KEM keys registered for conversation {}",
            conversation_id
        );

        Ok(response)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ASK AI (WITH DEK UNWRAPPING)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Send a message and get a response, automatically unwrapping DEK and decrypting token map
    pub async fn ask(
        &self,
        conversation_id: &str,
        message: &str,
        context_files: Option<Vec<String>>,
    ) -> AppResult<DecryptedAskResponse> {
        let request = AskRequest {
            message: message.to_string(),
            context_files,
            session_key: None,
        };

        let response: AskResponse = self
            .post(&format!("/conversations/{}/ask", conversation_id), &request)
            .await?;

        // Unwrap DEK and decrypt token map
        let decrypted = self.decrypt_response(response)?;

        Ok(decrypted)
    }

    /// Decrypt an ask response by unwrapping the DEK and decrypting the token map
    fn decrypt_response(&self, response: AskResponse) -> AppResult<DecryptedAskResponse> {
        // Get the DEK (either from KEM unwrapping or directly from response)
        let dek = if let (Some(wrapped_dek_b64), Some(ml_ct_b64)) =
            (&response.wrapped_dek, &response.ml_kem_ciphertext)
        {
            // Unwrap DEK using KEM
            self.unwrap_dek(wrapped_dek_b64, ml_ct_b64, response.kaz_kem_ciphertext.as_deref())?
        } else if let Some(session_key_b64) = &response.session_key {
            // DEK provided directly (legacy/fallback mode)
            Zeroizing::new(BASE64
                .decode(session_key_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid session key: {}", e)))?)
        } else {
            return Err(AppError::Crypto(
                "No DEK available in response (neither wrapped_dek nor session_key)".to_string(),
            ));
        };

        // Decrypt token map
        let encrypted_token_map = BASE64
            .decode(&response.encrypted_token_map)
            .map_err(|e| AppError::Crypto(format!("Invalid encrypted token map: {}", e)))?;

        let token_map = self.decrypt_token_map(&encrypted_token_map, &dek)?;

        // Restore original content from tokens
        let restored_content = self.restore_tokens(&response.content, &token_map);

        Ok(DecryptedAskResponse {
            user_message_id: response.user_message_id,
            assistant_message_id: response.assistant_message_id,
            content: restored_content,
            tokenized_content: response.content,
            role: response.role,
            tokens_detected: response.tokens_detected,
            created_at: response.created_at,
        })
    }

    /// Unwrap a KEM-encrypted DEK
    fn unwrap_dek(
        &self,
        wrapped_dek_b64: &str,
        ml_kem_ct_b64: &str,
        kaz_kem_ct_b64: Option<&str>,
    ) -> AppResult<Zeroizing<Vec<u8>>> {
        let ml_kem_sk = self
            .ml_kem_secret_key
            .read()
            .clone()
            .ok_or_else(|| AppError::Crypto("ML-KEM secret key not loaded".to_string()))?;

        let ml_kem_ct = BASE64
            .decode(ml_kem_ct_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid ML-KEM ciphertext: {}", e)))?;

        let wrapped_dek = BASE64
            .decode(wrapped_dek_b64)
            .map_err(|e| AppError::Crypto(format!("Invalid wrapped DEK: {}", e)))?;

        // ML-KEM decapsulation to get shared secret
        let ml_ss = ml_kem::decapsulate(&ml_kem_ct, &ml_kem_sk)
            .map_err(|e| AppError::Crypto(format!("ML-KEM decapsulation failed: {}", e)))?;

        // If KAZ-KEM was used, combine shared secrets
        let combined_ss = if let Some(kaz_ct_b64) = kaz_kem_ct_b64 {
            let kaz_kem_sk = self
                .kaz_kem_secret_key
                .read()
                .clone()
                .ok_or_else(|| AppError::Crypto("KAZ-KEM secret key not loaded".to_string()))?;

            let kaz_ct = BASE64
                .decode(kaz_ct_b64)
                .map_err(|e| AppError::Crypto(format!("Invalid KAZ-KEM ciphertext: {}", e)))?;

            let kaz_ss = ssdid_drive_crypto::kaz_kem::decapsulate(&kaz_ct, &kaz_kem_sk)
                .map_err(|e| AppError::Crypto(format!("KAZ-KEM decapsulation failed: {}", e)))?;

            // Combine ML-KEM and KAZ-KEM shared secrets
            let mut combined = Vec::with_capacity(ml_ss.len() + kaz_ss.len());
            combined.extend_from_slice(&ml_ss);
            combined.extend_from_slice(&kaz_ss);
            Zeroizing::new(combined)
        } else {
            ml_ss
        };

        // Derive KEK using HKDF (must match server-side derivation)
        let kek = hkdf_derive(&combined_ss, None, b"PII-Service-Hybrid-KEM-KEK-v1", KEY_SIZE)
            .map_err(|e| AppError::Crypto(format!("KEK derivation failed: {}", e)))?;

        // Unwrap DEK with AES-GCM
        let dek = decrypt_aes_gcm(&wrapped_dek, &kek)
            .map_err(|e| AppError::Crypto(format!("DEK unwrapping failed: {}", e)))?;

        Ok(dek)
    }

    /// Decrypt token map using DEK
    fn decrypt_token_map(
        &self,
        encrypted_map: &[u8],
        dek: &[u8],
    ) -> AppResult<std::collections::HashMap<String, String>> {
        // Token map format: nonce (12) || tag (16) || ciphertext
        if encrypted_map.len() < 28 {
            return Err(AppError::Crypto("Encrypted token map too short".to_string()));
        }

        let decrypted = decrypt_aes_gcm(encrypted_map, dek)
            .map_err(|e| AppError::Crypto(format!("Token map decryption failed: {}", e)))?;

        let token_map: std::collections::HashMap<String, String> =
            serde_json::from_slice(&decrypted)
                .map_err(|e| AppError::Crypto(format!("Invalid token map JSON: {}", e)))?;

        Ok(token_map)
    }

    /// Restore original PII values from tokens
    fn restore_tokens(
        &self,
        tokenized_text: &str,
        token_map: &std::collections::HashMap<String, String>,
    ) -> String {
        let mut restored = tokenized_text.to_string();
        for (token, value) in token_map {
            restored = restored.replace(token, value);
        }
        restored
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HTTP HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    async fn get<T: serde::de::DeserializeOwned>(&self, endpoint: &str) -> AppResult<T> {
        let url = format!("{}{}", self.base_url, endpoint);
        let mut request = self.client.get(&url);

        if let Some(token) = self.auth_token.read().as_ref() {
            request = request.header(header::AUTHORIZATION, format!("Bearer {}", token));
        }

        let response = request
            .header(header::ACCEPT, "application/json")
            .send()
            .await
            .map_err(|e| AppError::Network(e.to_string()))?;

        if response.status().is_success() {
            response
                .json()
                .await
                .map_err(|e| AppError::Network(format!("Failed to parse response: {}", e)))
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            Err(AppError::Network(format!(
                "PII service error ({}): {}",
                status, error_text
            )))
        }
    }

    async fn post<B: Serialize, T: serde::de::DeserializeOwned>(
        &self,
        endpoint: &str,
        body: &B,
    ) -> AppResult<T> {
        let url = format!("{}{}", self.base_url, endpoint);
        let mut request = self.client.post(&url);

        if let Some(token) = self.auth_token.read().as_ref() {
            request = request.header(header::AUTHORIZATION, format!("Bearer {}", token));
        }

        let response = request
            .header(header::CONTENT_TYPE, "application/json")
            .header(header::ACCEPT, "application/json")
            .json(body)
            .send()
            .await
            .map_err(|e| AppError::Network(e.to_string()))?;

        if response.status().is_success() {
            response
                .json()
                .await
                .map_err(|e| AppError::Network(format!("Failed to parse response: {}", e)))
        } else {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            Err(AppError::Network(format!(
                "PII service error ({}): {}",
                status, error_text
            )))
        }
    }
}

impl Drop for PiiServiceClient {
    fn drop(&mut self) {
        self.clear_kem_secret_keys();
    }
}
