//! OS keychain integration using keyring-rs

use crate::error::{AppError, AppResult};
use keyring::Entry;

const SERVICE_NAME: &str = "com.securesharing.desktop";

/// Key names for stored secrets
mod keys {
    pub const AUTH_TOKEN: &str = "auth_token";
    pub const REFRESH_TOKEN: &str = "refresh_token";
    pub const DEVICE_ID: &str = "device_id";
    pub const ENCRYPTED_MASTER_KEY: &str = "encrypted_master_key";
    pub const MK_NONCE: &str = "mk_nonce";
    pub const ENC_SALT: &str = "enc_salt";
    pub const BIOMETRIC_KEY: &str = "biometric_key";
}

/// OS keychain storage for sensitive data
pub struct KeyringStore {
    // No state needed - keyring-rs handles everything
}

impl KeyringStore {
    /// Create a new keyring store
    pub fn new() -> Self {
        Self {}
    }

    /// Create an entry for the given key
    fn entry(&self, key: &str) -> Result<Entry, keyring::Error> {
        Entry::new(SERVICE_NAME, key)
    }

    /// Store a secret in the keychain
    fn store(&self, key: &str, value: &str) -> AppResult<()> {
        let entry = self.entry(key)?;
        entry.set_password(value)?;
        tracing::debug!("Stored secret: {}", key);
        Ok(())
    }

    /// Get a secret from the keychain
    fn get(&self, key: &str) -> AppResult<String> {
        let entry = self.entry(key)?;
        let value = entry.get_password()?;
        Ok(value)
    }

    /// Delete a secret from the keychain
    fn delete(&self, key: &str) -> AppResult<()> {
        let entry = self.entry(key)?;
        match entry.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()), // Already deleted
            Err(e) => Err(e.into()),
        }
    }

    /// Check if a secret exists
    fn exists(&self, key: &str) -> AppResult<bool> {
        let entry = self.entry(key)?;
        match entry.get_password() {
            Ok(_) => Ok(true),
            Err(keyring::Error::NoEntry) => Ok(false),
            Err(e) => Err(e.into()),
        }
    }

    // Auth token
    pub fn store_auth_token(&self, token: &str) -> AppResult<()> {
        self.store(keys::AUTH_TOKEN, token)
    }

    pub fn get_auth_token(&self) -> AppResult<String> {
        self.get(keys::AUTH_TOKEN)
    }

    // Refresh token
    pub fn store_refresh_token(&self, token: &str) -> AppResult<()> {
        self.store(keys::REFRESH_TOKEN, token)
    }

    pub fn get_refresh_token(&self) -> AppResult<String> {
        self.get(keys::REFRESH_TOKEN)
    }

    // Device ID
    pub fn store_device_id(&self, id: &str) -> AppResult<()> {
        self.store(keys::DEVICE_ID, id)
    }

    pub fn get_device_id(&self) -> AppResult<String> {
        self.get(keys::DEVICE_ID)
    }

    // Encrypted master key
    pub fn store_encrypted_master_key(&self, key: &str) -> AppResult<()> {
        self.store(keys::ENCRYPTED_MASTER_KEY, key)
    }

    pub fn get_encrypted_master_key(&self) -> AppResult<String> {
        self.get(keys::ENCRYPTED_MASTER_KEY)
    }

    // Master key nonce
    pub fn store_mk_nonce(&self, nonce: &str) -> AppResult<()> {
        self.store(keys::MK_NONCE, nonce)
    }

    pub fn get_mk_nonce(&self) -> AppResult<String> {
        self.get(keys::MK_NONCE)
    }

    // Encryption salt (for password-based key derivation)
    pub fn store_enc_salt(&self, salt: &str) -> AppResult<()> {
        self.store(keys::ENC_SALT, salt)
    }

    pub fn get_enc_salt(&self) -> AppResult<String> {
        self.get(keys::ENC_SALT)
    }

    // Biometric key
    pub fn store_biometric_key(&self, key: &str) -> AppResult<()> {
        self.store(keys::BIOMETRIC_KEY, key)
    }

    pub fn get_biometric_key(&self) -> AppResult<String> {
        self.get(keys::BIOMETRIC_KEY)
    }

    pub fn has_biometric_key(&self) -> AppResult<bool> {
        self.exists(keys::BIOMETRIC_KEY)
    }

    /// Clear all stored secrets
    pub fn clear_all(&self) -> AppResult<()> {
        let keys = [
            keys::AUTH_TOKEN,
            keys::REFRESH_TOKEN,
            keys::DEVICE_ID,
            keys::ENCRYPTED_MASTER_KEY,
            keys::MK_NONCE,
            keys::ENC_SALT,
            keys::BIOMETRIC_KEY,
        ];

        for key in keys {
            let _ = self.delete(key); // Ignore errors for missing keys
        }

        tracing::info!("Cleared all keyring secrets");
        Ok(())
    }
}

impl Default for KeyringStore {
    fn default() -> Self {
        Self::new()
    }
}
