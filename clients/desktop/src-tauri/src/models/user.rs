//! User-related data models

use serde::{Deserialize, Serialize};
use std::fmt;

/// User account information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub email: String,
    pub name: String,
    pub tenant_id: String,
    pub created_at: String,
    pub updated_at: String,
}

/// Authentication credentials for login
/// Note: Debug is manually implemented to mask password
#[derive(Clone, Serialize, Deserialize)]
pub struct LoginCredentials {
    pub email: String,
    pub password: String,
    pub device_id: Option<String>,
}

impl fmt::Debug for LoginCredentials {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LoginCredentials")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .field("device_id", &self.device_id)
            .finish()
    }
}

/// Registration information
/// Note: Debug is manually implemented to mask password
#[derive(Clone, Serialize, Deserialize)]
pub struct RegistrationInfo {
    pub email: String,
    pub password: String,
    pub name: String,
    pub invitation_token: String,
}

impl fmt::Debug for RegistrationInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RegistrationInfo")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .field("name", &self.name)
            .field("invitation_token", &"[REDACTED]")
            .finish()
    }
}

/// Login response from API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginResponse {
    pub user: User,
    pub access_token: String,
    pub refresh_token: String,
    pub device_id: String,
    /// Encrypted key bundle (encrypted master key, etc.)
    pub key_bundle: KeyBundle,
}

/// Registration response from API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrationResponse {
    pub user: User,
    pub access_token: String,
    pub refresh_token: String,
    pub device_id: String,
}

/// Key bundle containing encrypted cryptographic keys
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyBundle {
    /// Encrypted master key (encrypted with derived key from password)
    pub encrypted_master_key: String,
    /// Nonce for master key encryption
    pub mk_nonce: String,
    /// Encrypted ML-KEM private key
    pub encrypted_ml_kem_sk: String,
    /// Encrypted ML-DSA private key
    pub encrypted_ml_dsa_sk: String,
    /// Encrypted KAZ-KEM private key
    pub encrypted_kaz_kem_sk: String,
    /// Encrypted KAZ-SIGN private key
    pub encrypted_kaz_sign_sk: String,
    /// ML-KEM public key
    pub ml_kem_pk: String,
    /// ML-DSA public key
    pub ml_dsa_pk: String,
    /// KAZ-KEM public key
    pub kaz_kem_pk: String,
    /// KAZ-SIGN public key
    pub kaz_sign_pk: String,
    /// Key derivation salt for password -> auth key
    pub auth_salt: String,
    /// Key derivation salt for password -> encryption key
    pub enc_salt: String,
}

/// Authentication status response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthStatus {
    pub is_authenticated: bool,
    pub is_locked: bool,
    pub user: Option<User>,
}

/// Session information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: String,
}

/// Request to update user profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProfileRequest {
    pub name: Option<String>,
}

/// Request to change password
/// Note: Debug is manually implemented to mask passwords
#[derive(Clone, Serialize, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

impl fmt::Debug for ChangePasswordRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChangePasswordRequest")
            .field("current_password", &"[REDACTED]")
            .field("new_password", &"[REDACTED]")
            .finish()
    }
}

/// A user's device/session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub name: Option<String>,
    pub device_type: String,
    pub last_active: String,
    pub created_at: String,
    pub is_current: bool,
}

/// Response for device list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceListResponse {
    pub devices: Vec<Device>,
}
