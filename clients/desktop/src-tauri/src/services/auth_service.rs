//! Authentication service (SSDID session model)
//!
//! Identity and signing are handled entirely by the SSDID Wallet.
//! This service only manages session tokens via the OS keyring.

use crate::error::AppResult;
use crate::models::User;
use crate::services::ApiClient;
use crate::storage::KeyringStore;
use std::sync::Arc;

/// Service for authentication operations
pub struct AuthService {
    api_client: Arc<ApiClient>,
    keyring: Arc<KeyringStore>,
}

impl AuthService {
    /// Create a new auth service
    pub fn new(
        api_client: Arc<ApiClient>,
        keyring: Arc<KeyringStore>,
    ) -> Self {
        Self {
            api_client,
            keyring,
        }
    }

    /// Save a session token (received after SSDID wallet authentication)
    pub fn save_session(&self, token: &str) -> AppResult<()> {
        self.keyring.store_auth_token(token)?;
        self.api_client.set_auth_token(Some(token.to_string()));
        tracing::info!("Session token saved");
        Ok(())
    }

    /// Get the current session token, if any
    pub fn get_session(&self) -> Option<String> {
        self.keyring.get_auth_token().ok()
    }

    /// Check if a session token exists
    pub fn is_authenticated(&self) -> bool {
        self.get_session().is_some()
    }

    /// Restore session on app startup (load token from keyring into API client)
    pub fn restore_session(&self) -> bool {
        if let Some(token) = self.get_session() {
            self.api_client.set_auth_token(Some(token));
            tracing::info!("Session restored from keyring");
            true
        } else {
            false
        }
    }

    /// Logout the current user
    pub async fn logout(&self) -> AppResult<()> {
        tracing::debug!("Logging out");

        // Call API to invalidate token (ignore errors if token already expired)
        let _ = self.api_client.post::<(), ()>("/auth/ssdid/logout", &()).await;

        // Clear stored credentials
        self.api_client.set_auth_token(None);
        self.keyring.clear_all()?;

        tracing::info!("Logout complete, session cleared");
        Ok(())
    }

    /// Get the current user from the API
    pub async fn get_current_user(&self) -> AppResult<User> {
        self.api_client.get::<User>("/users/me").await
    }
}
