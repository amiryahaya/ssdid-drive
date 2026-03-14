//! Application state management

use crate::error::{AppError, AppResult};
use crate::models::User;
use crate::services::{ApiClient, AuthService, BiometricService, CryptoService, FileService, NotificationService, PiiServiceClient, RecoveryService, SharingService, SyncService, TenantService};
use crate::storage::{Database, KeyringStore};
use parking_lot::RwLock;
use std::sync::Arc;

/// Global application state managed by Tauri
pub struct AppState {
    /// Current authenticated user
    current_user: RwLock<Option<User>>,

    /// API client for backend communication
    api_client: Arc<ApiClient>,

    /// Authentication service (SSDID session management)
    auth_service: Arc<AuthService>,

    /// Cryptographic service
    crypto_service: Arc<CryptoService>,

    /// File operations service
    file_service: Arc<FileService>,

    /// Sharing service
    sharing_service: Arc<SharingService>,

    /// Recovery service
    recovery_service: Arc<RecoveryService>,

    /// Notification service
    notification_service: Arc<NotificationService>,

    /// Tenant service
    tenant_service: Arc<TenantService>,

    /// Biometric service
    biometric_service: Arc<BiometricService>,

    /// PII service client
    pii_service: Arc<PiiServiceClient>,

    /// Sync service for offline mode
    sync_service: Arc<SyncService>,

    /// Local database for caching
    database: Arc<Database>,

    /// OS keychain integration
    keyring: Arc<KeyringStore>,

    /// Whether the app is locked (requires unlock)
    is_locked: RwLock<bool>,

    /// Pending OIDC nonce for deep link spoofing protection
    oidc_nonce: RwLock<Option<String>>,
}

impl AppState {
    /// Create a new application state instance
    pub fn new() -> AppResult<Self> {
        tracing::info!("Initializing application state");

        // Initialize database
        let database = Arc::new(Database::new()?);

        // Initialize keyring
        let keyring = Arc::new(KeyringStore::new());

        // Initialize API client
        let api_client = Arc::new(ApiClient::new()?);

        // Initialize crypto service
        let crypto_service = Arc::new(CryptoService::new()?);

        // Initialize auth service (simplified for SSDID)
        let auth_service = Arc::new(AuthService::new(
            api_client.clone(),
            keyring.clone(),
        ));

        // Initialize file service
        let file_service = Arc::new(FileService::new(
            api_client.clone(),
            crypto_service.clone(),
            database.clone(),
        ));

        // Initialize sharing service
        let sharing_service = Arc::new(SharingService::new(
            api_client.clone(),
            crypto_service.clone(),
            database.clone(),
        ));

        // Initialize recovery service
        let recovery_service = Arc::new(RecoveryService::new(api_client.clone()));

        // Initialize notification service
        let notification_service = Arc::new(NotificationService::new(api_client.clone()));

        // Initialize tenant service
        let tenant_service = Arc::new(TenantService::new(
            api_client.clone(),
            keyring.clone(),
        ));

        // Initialize biometric service (loads saved preference from database)
        let biometric_service = Arc::new(BiometricService::new(database.clone()));

        // Initialize PII service client
        let pii_service = Arc::new(PiiServiceClient::new()?);

        // Initialize sync service
        let sync_service = Arc::new(SyncService::new(database.clone()));

        // Set up token refresh callback
        let keyring_for_refresh = keyring.clone();
        let base_url_for_refresh = api_client.base_url().to_string();
        let refresh_callback: crate::services::RefreshCallback = Arc::new(move || {
            let keyring = keyring_for_refresh.clone();
            let base_url = base_url_for_refresh.clone();
            Box::pin(async move {
                // Get refresh token from keyring
                let refresh_token = keyring.get_refresh_token()?;

                #[derive(serde::Serialize)]
                struct RefreshRequest {
                    refresh_token: String,
                }

                #[derive(serde::Deserialize)]
                struct RefreshResponse {
                    access_token: String,
                    refresh_token: String,
                }

                // Build the request manually to avoid using the retry-enabled methods
                let refresh_url = format!("{}/auth/refresh", base_url);
                let client = reqwest::Client::new();
                let response = client
                    .post(&refresh_url)
                    .json(&RefreshRequest { refresh_token })
                    .send()
                    .await
                    .map_err(|e| crate::error::AppError::Network(e.to_string()))?;

                if !response.status().is_success() {
                    return Err(crate::error::AppError::Auth("Token refresh failed".to_string()));
                }

                let refresh_response: RefreshResponse = response
                    .json()
                    .await
                    .map_err(|e| crate::error::AppError::Network(e.to_string()))?;

                // Store new tokens
                keyring.store_auth_token(&refresh_response.access_token)?;
                keyring.store_refresh_token(&refresh_response.refresh_token)?;

                Ok(refresh_response.access_token)
            })
        });

        api_client.set_refresh_callback(refresh_callback);

        // Attempt to restore session from keyring
        let has_session = auth_service.restore_session();

        Ok(Self {
            current_user: RwLock::new(None),
            api_client,
            auth_service,
            crypto_service,
            file_service,
            sharing_service,
            recovery_service,
            notification_service,
            tenant_service,
            biometric_service,
            pii_service,
            sync_service,
            database,
            keyring,
            is_locked: RwLock::new(!has_session),
            oidc_nonce: RwLock::new(None),
        })
    }

    /// Get the current authenticated user
    pub fn current_user(&self) -> Option<User> {
        self.current_user.read().clone()
    }

    /// Set the current authenticated user
    pub fn set_current_user(&self, user: Option<User>) {
        *self.current_user.write() = user;
    }

    /// Check if a user is authenticated
    pub fn is_authenticated(&self) -> bool {
        self.current_user.read().is_some()
    }

    /// Check if the app is locked
    pub fn is_locked(&self) -> bool {
        *self.is_locked.read()
    }

    /// Lock the app
    pub fn lock(&self) {
        *self.is_locked.write() = true;
        tracing::info!("Application locked");
    }

    /// Unlock the app
    pub fn unlock(&self) {
        *self.is_locked.write() = false;
        tracing::info!("Application unlocked");
    }

    /// Generate and store a nonce for OIDC deep link verification
    pub fn generate_oidc_nonce(&self) -> String {
        let nonce = uuid::Uuid::new_v4().to_string();
        *self.oidc_nonce.write() = Some(nonce.clone());
        nonce
    }

    /// Validate and consume the OIDC nonce (single-use)
    pub fn validate_oidc_nonce(&self, nonce: &str) -> bool {
        let mut stored = self.oidc_nonce.write();
        if stored.as_deref() == Some(nonce) {
            *stored = None;
            true
        } else {
            false
        }
    }

    /// Complete login: save session, unlock, and fetch+cache user
    pub async fn complete_login(&self, token: &str) -> AppResult<()> {
        self.auth_service().save_session(token)?;
        self.unlock();
        match self.auth_service().get_current_user().await {
            Ok(user) => self.set_current_user(Some(user)),
            Err(e) => tracing::warn!("Failed to fetch user after login: {}", e),
        }
        Ok(())
    }

    /// Get the API client
    pub fn api_client(&self) -> &Arc<ApiClient> {
        &self.api_client
    }

    /// Get the auth service
    pub fn auth_service(&self) -> &Arc<AuthService> {
        &self.auth_service
    }

    /// Get the crypto service
    pub fn crypto_service(&self) -> &Arc<CryptoService> {
        &self.crypto_service
    }

    /// Get the file service
    pub fn file_service(&self) -> &Arc<FileService> {
        &self.file_service
    }

    /// Get the sharing service
    pub fn sharing_service(&self) -> &Arc<SharingService> {
        &self.sharing_service
    }

    /// Get the recovery service
    pub fn recovery_service(&self) -> &Arc<RecoveryService> {
        &self.recovery_service
    }

    /// Get the notification service
    pub fn notification_service(&self) -> &Arc<NotificationService> {
        &self.notification_service
    }

    /// Get the tenant service
    pub fn tenant_service(&self) -> &Arc<TenantService> {
        &self.tenant_service
    }

    /// Get the biometric service
    pub fn biometric_service(&self) -> &Arc<BiometricService> {
        &self.biometric_service
    }

    /// Get the PII service client
    pub fn pii_service(&self) -> &Arc<PiiServiceClient> {
        &self.pii_service
    }

    /// Get the sync service
    pub fn sync_service(&self) -> &Arc<SyncService> {
        &self.sync_service
    }

    /// Get the database
    pub fn database(&self) -> &Arc<Database> {
        &self.database
    }

    /// Get the keyring store
    pub fn keyring(&self) -> &Arc<KeyringStore> {
        &self.keyring
    }

    /// Require authentication - returns error if not authenticated
    pub fn require_auth(&self) -> AppResult<User> {
        self.current_user
            .read()
            .clone()
            .ok_or(AppError::NotAuthenticated)
    }

    /// Require unlocked state - returns error if locked
    pub fn require_unlocked(&self) -> AppResult<()> {
        if *self.is_locked.read() {
            return Err(AppError::Auth("Application is locked".to_string()));
        }
        Ok(())
    }
}

// AppState is now naturally Send + Sync because all its fields are:
// - RwLock<T> from parking_lot is Send + Sync when T is Send
// - Arc<T> is Send + Sync when T is Send + Sync
// - All services use thread-safe primitives
// - Database now uses on-demand connections instead of holding !Send Connection
