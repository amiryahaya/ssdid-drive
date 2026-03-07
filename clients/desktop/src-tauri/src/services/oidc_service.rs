//! OIDC authentication service

use crate::error::{AppError, AppResult};
use crate::models::{
    AuthProvider, AuthProvidersResponse, OidcAuthorizeRequest, OidcAuthorizeResponse,
    OidcCallbackRequest, OidcCallbackResponse, OidcRegisterRequest, OidcRegisterResponse,
    VaultKeyBundle,
};
use crate::services::{ApiClient, CryptoService};
use parking_lot::RwLock;
use std::sync::Arc;

/// Service for OIDC authentication operations
pub struct OidcService {
    api_client: Arc<ApiClient>,
    crypto_service: Arc<CryptoService>,
    /// In-flight OIDC state for validation
    pending_state: RwLock<Option<String>>,
}

impl OidcService {
    /// Create a new OIDC service
    pub fn new(api_client: Arc<ApiClient>, crypto_service: Arc<CryptoService>) -> Self {
        Self {
            api_client,
            crypto_service,
            pending_state: RwLock::new(None),
        }
    }

    /// Get available auth providers for a tenant
    pub async fn get_providers(&self, tenant_slug: &str) -> AppResult<Vec<AuthProvider>> {
        let response: AuthProvidersResponse = self
            .api_client
            .get_unauth(&format!("/auth/providers?tenant_slug={}", tenant_slug))
            .await?;
        Ok(response.providers)
    }

    /// Begin OIDC authorization flow
    pub async fn begin_authorize(&self, provider_id: &str) -> AppResult<OidcAuthorizeResponse> {
        let request = OidcAuthorizeRequest {
            provider_id: provider_id.to_string(),
            redirect_uri: "ssdid-drive://oidc/callback".to_string(),
        };

        let response: OidcAuthorizeResponse = self
            .api_client
            .post_unauth("/auth/oidc/authorize", &request)
            .await?;

        // Store state for validation on callback
        *self.pending_state.write() = Some(response.state.clone());

        Ok(response)
    }

    /// Validate and clear the pending OIDC state
    pub fn validate_state(&self, state: &str) -> AppResult<()> {
        let pending = self.pending_state.write().take();
        match pending {
            Some(expected) if expected == state => Ok(()),
            Some(_) => Err(AppError::Auth("OIDC state mismatch".to_string())),
            None => Err(AppError::Auth("No pending OIDC authorization".to_string())),
        }
    }

    /// Handle OIDC callback (exchange code for tokens)
    pub async fn handle_callback(&self, code: &str, state: &str) -> AppResult<OidcCallbackResponse> {
        // Validate state parameter
        self.validate_state(state)?;

        let request = OidcCallbackRequest {
            code: code.to_string(),
            state: state.to_string(),
        };

        let response: OidcCallbackResponse = self
            .api_client
            .post_unauth("/auth/oidc/callback", &request)
            .await?;

        Ok(response)
    }

    /// Derive vault key from OIDC key material
    pub fn derive_vault_key(&self, key_material: &str, key_salt: &str) -> AppResult<Vec<u8>> {
        use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

        let material_bytes = BASE64
            .decode(key_material)
            .map_err(|e| AppError::Crypto(format!("Failed to decode key_material: {}", e)))?;
        let salt_bytes = BASE64
            .decode(key_salt)
            .map_err(|e| AppError::Crypto(format!("Failed to decode key_salt: {}", e)))?;

        // HKDF-SHA384: key_material + salt → vault_key
        let vault_key = ssdid_drive_crypto::symmetric::hkdf_derive(
            &material_bytes,
            &salt_bytes,
            b"ssdid-drive-vault-key",
        )
        .map_err(|e| AppError::Crypto(format!("HKDF derivation failed: {}", e)))?;

        Ok(vault_key)
    }

    /// Complete OIDC registration for a new user
    pub async fn complete_registration(
        &self,
        request: OidcRegisterRequest,
    ) -> AppResult<OidcRegisterResponse> {
        let response: OidcRegisterResponse = self
            .api_client
            .post_unauth("/auth/oidc/register", &request)
            .await?;
        Ok(response)
    }
}
