//! WebAuthn authentication service

use crate::error::{AppError, AppResult};
use crate::models::{
    WebAuthnLoginBeginResponse, WebAuthnLoginCompleteRequest, WebAuthnLoginResponse,
    WebAuthnRegisterBeginResponse, WebAuthnRegisterCompleteRequest,
};
use crate::services::{ApiClient, CryptoService};
use std::sync::Arc;

/// Service for WebAuthn (passkey) authentication operations
pub struct WebAuthnService {
    api_client: Arc<ApiClient>,
    crypto_service: Arc<CryptoService>,
}

impl WebAuthnService {
    /// Create a new WebAuthn service
    pub fn new(api_client: Arc<ApiClient>, crypto_service: Arc<CryptoService>) -> Self {
        Self {
            api_client,
            crypto_service,
        }
    }

    /// Begin WebAuthn registration (public - during signup)
    pub async fn register_begin(
        &self,
        email: &str,
        tenant_slug: Option<&str>,
    ) -> AppResult<WebAuthnRegisterBeginResponse> {
        #[derive(serde::Serialize)]
        struct Request {
            email: String,
            #[serde(skip_serializing_if = "Option::is_none")]
            tenant_slug: Option<String>,
        }

        let request = Request {
            email: email.to_string(),
            tenant_slug: tenant_slug.map(|s| s.to_string()),
        };

        self.api_client
            .post_unauth("/auth/webauthn/register/begin", &request)
            .await
    }

    /// Complete WebAuthn registration
    pub async fn register_complete(
        &self,
        request: WebAuthnRegisterCompleteRequest,
    ) -> AppResult<WebAuthnLoginResponse> {
        self.api_client
            .post_unauth("/auth/webauthn/register/complete", &request)
            .await
    }

    /// Begin WebAuthn login
    pub async fn login_begin(
        &self,
        email: Option<&str>,
    ) -> AppResult<WebAuthnLoginBeginResponse> {
        #[derive(serde::Serialize)]
        struct Request {
            #[serde(skip_serializing_if = "Option::is_none")]
            email: Option<String>,
        }

        let request = Request {
            email: email.map(|e| e.to_string()),
        };

        self.api_client
            .post_unauth("/auth/webauthn/login/begin", &request)
            .await
    }

    /// Complete WebAuthn login
    pub async fn login_complete(
        &self,
        request: WebAuthnLoginCompleteRequest,
    ) -> AppResult<WebAuthnLoginResponse> {
        self.api_client
            .post_unauth("/auth/webauthn/login/complete", &request)
            .await
    }

    /// Begin adding a credential to an existing account (authenticated)
    pub async fn credential_begin(&self) -> AppResult<WebAuthnRegisterBeginResponse> {
        self.api_client
            .post::<(), WebAuthnRegisterBeginResponse>(
                "/auth/webauthn/credentials/begin",
                &(),
            )
            .await
    }

    /// Complete adding a credential (authenticated)
    pub async fn credential_complete(
        &self,
        request: WebAuthnRegisterCompleteRequest,
    ) -> AppResult<serde_json::Value> {
        self.api_client
            .post("/auth/webauthn/credentials/complete", &request)
            .await
    }

    /// Derive wrapping key from PRF output (for PRF-capable platforms)
    pub fn derive_prf_wrapping_key(&self, prf_output: &[u8]) -> AppResult<Vec<u8>> {
        let wrapping_key = securesharing_crypto::symmetric::hkdf_derive(
            prf_output,
            b"securesharing-webauthn-mk",
            b"wrapping-key",
        )
        .map_err(|e| AppError::Crypto(format!("PRF key derivation failed: {}", e)))?;

        Ok(wrapping_key)
    }
}
