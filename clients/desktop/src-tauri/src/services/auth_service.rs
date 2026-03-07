//! Authentication service

use crate::error::{AppError, AppResult};
use crate::models::{
    ChangePasswordRequest, Device, DeviceListResponse, KeyBundle, LoginCredentials,
    LoginResponse, RegistrationInfo, RegistrationResponse, UpdateProfileRequest, User,
};
use crate::services::{ApiClient, CryptoService};
use crate::storage::KeyringStore;
use parking_lot::RwLock;
use securesharing_crypto::symmetric::{
    tiered_kdf_create_salt, tiered_kdf_derive, KdfProfile, TIERED_KDF_WIRE_SALT_SIZE,
};
use std::sync::Arc;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Decrypted session keys stored in memory (zeroized on drop)
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct SessionKeys {
    /// Decrypted ML-KEM private key (base64)
    ml_kem_sk: String,
    /// Decrypted ML-DSA private key (base64)
    ml_dsa_sk: String,
    /// Decrypted KAZ-KEM private key (base64)
    kaz_kem_sk: String,
    /// Decrypted KAZ-SIGN private key (base64)
    kaz_sign_sk: String,
}

impl SessionKeys {
    /// Create new session keys
    pub fn new(ml_kem_sk: String, ml_dsa_sk: String, kaz_kem_sk: String, kaz_sign_sk: String) -> Self {
        Self { ml_kem_sk, ml_dsa_sk, kaz_kem_sk, kaz_sign_sk }
    }

    /// Get ML-KEM secret key
    pub fn ml_kem_sk(&self) -> &str {
        &self.ml_kem_sk
    }

    /// Get ML-DSA secret key
    pub fn ml_dsa_sk(&self) -> &str {
        &self.ml_dsa_sk
    }

    /// Get KAZ-KEM secret key
    pub fn kaz_kem_sk(&self) -> &str {
        &self.kaz_kem_sk
    }

    /// Get KAZ-SIGN secret key
    pub fn kaz_sign_sk(&self) -> &str {
        &self.kaz_sign_sk
    }
}

/// Service for authentication operations
pub struct AuthService {
    api_client: Arc<ApiClient>,
    keyring: Arc<KeyringStore>,
    crypto_service: Arc<CryptoService>,
    /// Decrypted session keys (only available when unlocked)
    session_keys: RwLock<Option<SessionKeys>>,
}

impl AuthService {
    /// Create a new auth service
    pub fn new(
        api_client: Arc<ApiClient>,
        keyring: Arc<KeyringStore>,
        crypto_service: Arc<CryptoService>,
    ) -> Self {
        Self {
            api_client,
            keyring,
            crypto_service,
            session_keys: RwLock::new(None),
        }
    }

    /// Login with credentials
    pub async fn login(&self, credentials: LoginCredentials) -> AppResult<LoginResponse> {
        tracing::debug!("Attempting login for: {}", credentials.email);

        // Call API to login
        let response: LoginResponse = self.api_client.post("/auth/login", &credentials).await?;

        // Store auth token
        self.api_client.set_auth_token(Some(response.access_token.clone()));

        // Store tokens in keyring
        self.keyring.store_auth_token(&response.access_token)?;
        self.keyring.store_refresh_token(&response.refresh_token)?;
        self.keyring.store_device_id(&response.device_id)?;

        // Derive encryption key from password
        let enc_key = self.crypto_service.derive_encryption_key(
            &credentials.password,
            &response.key_bundle.enc_salt,
        )?;

        // Decrypt master key and store in CryptoService
        let master_key = self.crypto_service.decrypt_master_key(
            &response.key_bundle.encrypted_master_key,
            &response.key_bundle.mk_nonce,
            &enc_key,
        )?;

        // Store master key in crypto service for session
        self.crypto_service.set_master_key(master_key.clone())?;

        // Decrypt private keys and store in session
        let ml_kem_sk = self.crypto_service.decrypt_private_key(
            &response.key_bundle.encrypted_ml_kem_sk,
            &master_key,
        )?;
        let ml_dsa_sk = self.crypto_service.decrypt_private_key(
            &response.key_bundle.encrypted_ml_dsa_sk,
            &master_key,
        )?;
        let kaz_kem_sk = self.crypto_service.decrypt_private_key(
            &response.key_bundle.encrypted_kaz_kem_sk,
            &master_key,
        )?;
        let kaz_sign_sk = self.crypto_service.decrypt_private_key(
            &response.key_bundle.encrypted_kaz_sign_sk,
            &master_key,
        )?;

        // Store decrypted keys in session (base64 encoded, zeroized on drop)
        use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
        *self.session_keys.write() = Some(SessionKeys::new(
            BASE64.encode(&ml_kem_sk),
            BASE64.encode(&ml_dsa_sk),
            BASE64.encode(&kaz_kem_sk),
            BASE64.encode(&kaz_sign_sk),
        ));

        // Store encrypted master key info in keyring for biometric unlock
        self.keyring.store_encrypted_master_key(&response.key_bundle.encrypted_master_key)?;
        self.keyring.store_mk_nonce(&response.key_bundle.mk_nonce)?;
        self.keyring.store_enc_salt(&response.key_bundle.enc_salt)?;

        // Best-effort KDF profile upgrade
        if let Err(e) = self.upgrade_kdf_profile_if_needed(
            &credentials.password, &master_key, &response.key_bundle.enc_salt,
        ).await {
            tracing::warn!("KDF profile upgrade failed (non-fatal): {}", e);
        }

        tracing::info!("Login successful, master key and session keys loaded");

        Ok(response)
    }

    /// Silently upgrade the KDF profile if the device supports a stronger one.
    /// Desktop always uses Argon2idStandard (profile 0x01). If the current salt
    /// uses a weaker profile or is legacy format, re-encrypt the master key with
    /// the stronger profile, update the server, and save locally.
    async fn upgrade_kdf_profile_if_needed(
        &self,
        password: &str,
        master_key: &[u8],
        current_enc_salt: &str,
    ) -> AppResult<()> {
        use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

        let current_salt = BASE64.decode(current_enc_salt)
            .map_err(|e| AppError::Crypto(format!("Failed to decode salt: {}", e)))?;

        // Desktop always targets Argon2idStandard
        let device_profile = KdfProfile::Argon2idStandard;

        let needs_upgrade = if current_salt.len() == TIERED_KDF_WIRE_SALT_SIZE {
            match KdfProfile::from_byte(current_salt[0]) {
                Ok(current) => current.profile_byte() > device_profile.profile_byte(),
                Err(_) => true,
            }
        } else {
            true // Legacy salt always needs upgrade
        };

        if !needs_upgrade { return Ok(()); }

        // Generate new salt + derive new key with stronger profile
        let new_salt = tiered_kdf_create_salt(device_profile);
        let mut new_enc_key = tiered_kdf_derive(password.as_bytes(), &new_salt)
            .map_err(|e| AppError::Crypto(format!("KDF derive failed: {}", e)))?;

        // Re-encrypt master key
        let (new_encrypted_mk, new_mk_nonce) =
            self.crypto_service.encrypt_master_key(master_key, &new_enc_key)?;

        // SECURITY: Zeroize derived key after use
        new_enc_key.zeroize();

        // Update server via PUT /me/keys
        #[derive(serde::Serialize)]
        struct UpdateKeysRequest {
            encrypted_master_key: String,
            key_derivation_salt: String,
        }
        let request = UpdateKeysRequest {
            encrypted_master_key: new_encrypted_mk.clone(),
            key_derivation_salt: BASE64.encode(&new_salt),
        };
        let _: serde_json::Value = self.api_client.put("/me/keys", &request).await?;

        // Update local keyring
        self.keyring.store_encrypted_master_key(&new_encrypted_mk)?;
        self.keyring.store_mk_nonce(&new_mk_nonce)?;
        self.keyring.store_enc_salt(&BASE64.encode(&new_salt))?;

        tracing::info!("Upgraded KDF profile to Argon2idStandard");
        Ok(())
    }

    /// Register a new user
    pub async fn register(&self, info: RegistrationInfo) -> AppResult<RegistrationResponse> {
        tracing::debug!("Attempting registration for: {}", info.email);

        // Generate PQC key pairs
        let (ml_kem_pk, ml_kem_sk) = self.crypto_service.generate_ml_kem_keypair()?;
        let (ml_dsa_pk, ml_dsa_sk) = self.crypto_service.generate_ml_dsa_keypair()?;
        let (kaz_kem_pk, kaz_kem_sk) = self.crypto_service.generate_kaz_kem_keypair()?;
        let (kaz_sign_pk, kaz_sign_sk) = self.crypto_service.generate_kaz_sign_keypair()?;

        // Generate master key
        let master_key = self.crypto_service.generate_master_key()?;

        // Derive keys from password
        let (auth_salt, auth_key) = self.crypto_service.derive_auth_key(&info.password)?;
        let (enc_salt, enc_key) = self.crypto_service.derive_encryption_key_with_salt(&info.password)?;

        // Encrypt master key
        let (encrypted_mk, mk_nonce) = self.crypto_service.encrypt_master_key(&master_key, &enc_key)?;

        // Encrypt private keys with master key
        let encrypted_ml_kem_sk = self.crypto_service.encrypt_private_key(&ml_kem_sk, &master_key)?;
        let encrypted_ml_dsa_sk = self.crypto_service.encrypt_private_key(&ml_dsa_sk, &master_key)?;
        let encrypted_kaz_kem_sk = self.crypto_service.encrypt_private_key(&kaz_kem_sk, &master_key)?;
        let encrypted_kaz_sign_sk = self.crypto_service.encrypt_private_key(&kaz_sign_sk, &master_key)?;

        // Build registration request
        #[derive(serde::Serialize)]
        struct RegisterRequest {
            email: String,
            password_hash: String,
            name: String,
            invitation_token: String,
            key_bundle: RegisterKeyBundle,
        }

        #[derive(serde::Serialize)]
        struct RegisterKeyBundle {
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

        let request = RegisterRequest {
            email: info.email,
            password_hash: auth_key,
            name: info.name,
            invitation_token: info.invitation_token,
            key_bundle: RegisterKeyBundle {
                encrypted_master_key: encrypted_mk,
                mk_nonce,
                encrypted_ml_kem_sk,
                encrypted_ml_dsa_sk,
                encrypted_kaz_kem_sk,
                encrypted_kaz_sign_sk,
                ml_kem_pk: ml_kem_pk.clone(),
                ml_dsa_pk: ml_dsa_pk.clone(),
                kaz_kem_pk: kaz_kem_pk.clone(),
                kaz_sign_pk: kaz_sign_pk.clone(),
                auth_salt,
                enc_salt,
            },
        };

        // Call API
        let response: RegistrationResponse = self.api_client.post("/auth/register", &request).await?;

        // Store tokens
        self.api_client.set_auth_token(Some(response.access_token.clone()));
        self.keyring.store_auth_token(&response.access_token)?;
        self.keyring.store_refresh_token(&response.refresh_token)?;
        self.keyring.store_device_id(&response.device_id)?;

        // Store master key in crypto service
        self.crypto_service.set_master_key(master_key)?;

        // Store session keys (already base64 from keypair generation, zeroized on drop)
        *self.session_keys.write() = Some(SessionKeys::new(
            ml_kem_sk,
            ml_dsa_sk,
            kaz_kem_sk,
            kaz_sign_sk,
        ));

        tracing::info!("Registration successful");

        Ok(response)
    }

    /// Logout the current user
    pub async fn logout(&self) -> AppResult<()> {
        tracing::debug!("Logging out");

        // Call API to invalidate token
        let _ = self.api_client.post::<(), ()>("/auth/logout", &()).await;

        // Clear master key from memory
        self.crypto_service.clear_master_key();

        // Clear session keys
        *self.session_keys.write() = None;

        // Clear stored credentials
        self.api_client.set_auth_token(None);
        self.keyring.clear_all()?;

        tracing::info!("Logout complete, all keys cleared");

        Ok(())
    }

    /// Get the decrypted signing keys for creating signatures
    pub fn get_signing_keys(&self) -> AppResult<(String, String)> {
        let keys = self.session_keys.read();
        let keys = keys.as_ref().ok_or_else(|| {
            AppError::Auth("Session keys not available. Please login first.".to_string())
        })?;

        Ok((keys.ml_dsa_sk().to_string(), keys.kaz_sign_sk().to_string()))
    }

    /// Get the decrypted KEM keys for decapsulation
    pub fn get_kem_keys(&self) -> AppResult<(String, String)> {
        let keys = self.session_keys.read();
        let keys = keys.as_ref().ok_or_else(|| {
            AppError::Auth("Session keys not available. Please login first.".to_string())
        })?;

        Ok((keys.ml_kem_sk().to_string(), keys.kaz_kem_sk().to_string()))
    }

    /// Check if session keys are available
    pub fn has_session_keys(&self) -> bool {
        self.session_keys.read().is_some()
    }

    /// Attempt biometric unlock
    ///
    /// NOTE: Biometric unlock is not yet implemented. This function returns
    /// false until platform-specific biometric authentication is integrated.
    pub async fn unlock_with_biometric(&self) -> AppResult<bool> {
        // Biometric unlock requires platform-specific implementation:
        // - macOS: Touch ID via LocalAuthentication framework
        // - Windows: Windows Hello via Windows.Security.Credentials
        // - Linux: libsecret or similar
        //
        // Until implemented, return false to indicate biometric is not available
        // This prevents confusing UX where users think biometric is configured
        Ok(false)
    }

    /// Check if biometric unlock is available on this platform
    pub fn is_biometric_available(&self) -> bool {
        #[cfg(target_os = "macos")]
        {
            // Check Touch ID via bioutil
            std::process::Command::new("bioutil")
                .args(["-c"])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false)
        }

        #[cfg(target_os = "windows")]
        {
            // Check Windows Hello availability synchronously
            use windows::Security::Credentials::UI::{
                UserConsentVerifier, UserConsentVerifierAvailability,
            };
            UserConsentVerifier::CheckAvailabilityAsync()
                .and_then(|op| op.get())
                .map(|a| a == UserConsentVerifierAvailability::Available)
                .unwrap_or(false)
        }

        #[cfg(not(any(target_os = "windows", target_os = "macos")))]
        {
            false
        }
    }

    /// Refresh the auth token
    pub async fn refresh_token(&self) -> AppResult<String> {
        let refresh_token = self.keyring.get_refresh_token()?;

        #[derive(serde::Serialize)]
        struct RefreshRequest {
            refresh_token: String,
        }

        #[derive(serde::Deserialize)]
        struct RefreshResponse {
            access_token: String,
            refresh_token: String,
        }

        let request = RefreshRequest { refresh_token };
        let response: RefreshResponse = self.api_client.post("/auth/refresh", &request).await?;

        // Update stored tokens
        self.api_client.set_auth_token(Some(response.access_token.clone()));
        self.keyring.store_auth_token(&response.access_token)?;
        self.keyring.store_refresh_token(&response.refresh_token)?;

        Ok(response.access_token)
    }

    /// Change the user's password
    ///
    /// This re-encrypts the master key and all private keys with the new password
    pub async fn change_password(&self, request: ChangePasswordRequest) -> AppResult<()> {
        tracing::debug!("Attempting password change");

        // Verify current password by deriving keys and checking we can decrypt
        let enc_salt = self.keyring.get_enc_salt()?;
        let enc_key = self.crypto_service.derive_encryption_key(&request.current_password, &enc_salt)?;

        // Decrypt master key with current password to verify
        let encrypted_mk = self.keyring.get_encrypted_master_key()?;
        let mk_nonce = self.keyring.get_mk_nonce()?;
        let master_key = self.crypto_service.decrypt_master_key(&encrypted_mk, &mk_nonce, &enc_key)?;

        // Derive new keys from new password
        let (new_auth_salt, new_auth_key) = self.crypto_service.derive_auth_key(&request.new_password)?;
        let (new_enc_salt, new_enc_key) = self.crypto_service.derive_encryption_key_with_salt(&request.new_password)?;

        // Re-encrypt master key with new encryption key
        let (new_encrypted_mk, new_mk_nonce) = self.crypto_service.encrypt_master_key(&master_key, &new_enc_key)?;

        // Build password change request for API
        #[derive(serde::Serialize)]
        struct ApiChangePasswordRequest {
            new_password_hash: String,
            encrypted_master_key: String,
            mk_nonce: String,
            auth_salt: String,
            enc_salt: String,
        }

        let api_request = ApiChangePasswordRequest {
            new_password_hash: new_auth_key,
            encrypted_master_key: new_encrypted_mk.clone(),
            mk_nonce: new_mk_nonce.clone(),
            auth_salt: new_auth_salt,
            enc_salt: new_enc_salt.clone(),
        };

        // Call API to update password
        self.api_client.post::<_, ()>("/auth/change-password", &api_request).await?;

        // Update local keyring with new encrypted master key
        self.keyring.store_encrypted_master_key(&new_encrypted_mk)?;
        self.keyring.store_mk_nonce(&new_mk_nonce)?;
        self.keyring.store_enc_salt(&new_enc_salt)?;

        tracing::info!("Password changed successfully");
        Ok(())
    }

    /// Update user profile
    pub async fn update_profile(&self, request: UpdateProfileRequest) -> AppResult<User> {
        tracing::debug!("Updating user profile");

        let user: User = self.api_client.put("/users/me", &request).await?;

        tracing::info!("Profile updated successfully");
        Ok(user)
    }

    /// List all devices/sessions for the current user
    pub async fn list_devices(&self) -> AppResult<Vec<Device>> {
        tracing::debug!("Fetching device list");

        let response: DeviceListResponse = self.api_client.get("/devices").await?;

        // Mark current device
        let current_device_id = self.keyring.get_device_id().ok();
        let devices: Vec<Device> = response
            .devices
            .into_iter()
            .map(|mut d| {
                d.is_current = current_device_id.as_ref() == Some(&d.id);
                d
            })
            .collect();

        Ok(devices)
    }

    /// Login with a vault-based key bundle (used by OIDC and non-PRF WebAuthn)
    ///
    /// The vault_key is used directly to decrypt the master key (no password derivation).
    pub async fn login_with_vault_key_bundle(
        &self,
        access_token: &str,
        refresh_token: &str,
        device_id: &str,
        encrypted_master_key: &str,
        mk_nonce: &str,
        decryption_key: &[u8],
        encrypted_private_keys: &crate::models::EncryptedPrivateKeys,
    ) -> AppResult<()> {
        use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

        // Store tokens
        self.api_client.set_auth_token(Some(access_token.to_string()));
        self.keyring.store_auth_token(access_token)?;
        self.keyring.store_refresh_token(refresh_token)?;
        self.keyring.store_device_id(device_id)?;

        // Decrypt master key using the provided key (vault key or PRF wrapping key)
        let master_key = self.crypto_service.decrypt_master_key(
            encrypted_master_key,
            mk_nonce,
            decryption_key,
        )?;

        // Store master key in crypto service
        self.crypto_service.set_master_key(master_key.clone())?;

        // Decrypt private keys
        let ml_kem_sk = self.crypto_service.decrypt_private_key(
            &encrypted_private_keys.encrypted_ml_kem_sk,
            &master_key,
        )?;
        let ml_dsa_sk = self.crypto_service.decrypt_private_key(
            &encrypted_private_keys.encrypted_ml_dsa_sk,
            &master_key,
        )?;
        let kaz_kem_sk = self.crypto_service.decrypt_private_key(
            &encrypted_private_keys.encrypted_kaz_kem_sk,
            &master_key,
        )?;
        let kaz_sign_sk = self.crypto_service.decrypt_private_key(
            &encrypted_private_keys.encrypted_kaz_sign_sk,
            &master_key,
        )?;

        // Store session keys
        *self.session_keys.write() = Some(SessionKeys::new(
            BASE64.encode(&ml_kem_sk),
            BASE64.encode(&ml_dsa_sk),
            BASE64.encode(&kaz_kem_sk),
            BASE64.encode(&kaz_sign_sk),
        ));

        // Store encrypted MK info for biometric unlock
        self.keyring.store_encrypted_master_key(encrypted_master_key)?;
        self.keyring.store_mk_nonce(mk_nonce)?;

        tracing::info!("Vault-based login successful, session keys loaded");
        Ok(())
    }

    /// Set session keys from raw key material (used during OIDC registration)
    pub fn set_session_keys_from_raw(
        &self,
        ml_kem_sk: &str,
        ml_dsa_sk: &str,
        kaz_kem_sk: &str,
        kaz_sign_sk: &str,
    ) -> AppResult<()> {
        *self.session_keys.write() = Some(SessionKeys::new(
            ml_kem_sk.to_string(),
            ml_dsa_sk.to_string(),
            kaz_kem_sk.to_string(),
            kaz_sign_sk.to_string(),
        ));
        Ok(())
    }

    /// Revoke a device/session
    pub async fn revoke_device(&self, device_id: &str) -> AppResult<()> {
        tracing::debug!("Revoking device: {}", device_id);

        // Prevent revoking current device
        if let Ok(current_id) = self.keyring.get_device_id() {
            if current_id == device_id {
                return Err(AppError::Validation(
                    "Cannot revoke current device. Use logout instead.".to_string(),
                ));
            }
        }

        self.api_client
            .delete::<()>(&format!("/devices/{}", device_id))
            .await?;

        tracing::info!("Device revoked: {}", device_id);
        Ok(())
    }
}
