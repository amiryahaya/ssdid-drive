//! Error types for the SSDID Drive Desktop application

use serde::Serialize;
use thiserror::Error;

/// Application-wide result type
pub type AppResult<T> = Result<T, AppError>;

/// Application error types
#[derive(Error, Debug)]
pub enum AppError {
    #[error("Authentication error: {0}")]
    Auth(String),

    #[error("Crypto error: {0}")]
    Crypto(String),

    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Network error: {0}")]
    Network(String),

    #[error("File error: {0}")]
    File(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("User not authenticated")]
    NotAuthenticated,

    #[error("Session expired")]
    SessionExpired,

    #[error("Keyring error: {0}")]
    Keyring(String),

    #[error("Database error: {0}")]
    Database(String),
}

/// Serializable error for Tauri commands
#[derive(Serialize)]
pub struct CommandError {
    pub code: String,
    pub message: String,
}

impl From<AppError> for CommandError {
    fn from(err: AppError) -> Self {
        let code = match &err {
            AppError::Auth(_) => "AUTH_ERROR",
            AppError::Crypto(_) => "CRYPTO_ERROR",
            AppError::Storage(_) => "STORAGE_ERROR",
            AppError::Network(_) => "NETWORK_ERROR",
            AppError::File(_) => "FILE_ERROR",
            AppError::Validation(_) => "VALIDATION_ERROR",
            AppError::NotFound(_) => "NOT_FOUND",
            AppError::PermissionDenied(_) => "PERMISSION_DENIED",
            AppError::Internal(_) => "INTERNAL_ERROR",
            AppError::NotAuthenticated => "NOT_AUTHENTICATED",
            AppError::SessionExpired => "SESSION_EXPIRED",
            AppError::Keyring(_) => "KEYRING_ERROR",
            AppError::Database(_) => "DATABASE_ERROR",
        };

        Self {
            code: code.to_string(),
            message: err.to_string(),
        }
    }
}

impl From<reqwest::Error> for AppError {
    fn from(err: reqwest::Error) -> Self {
        AppError::Network(err.to_string())
    }
}

impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        AppError::File(err.to_string())
    }
}

impl From<rusqlite::Error> for AppError {
    fn from(err: rusqlite::Error) -> Self {
        AppError::Database(err.to_string())
    }
}

impl From<keyring::Error> for AppError {
    fn from(err: keyring::Error) -> Self {
        AppError::Keyring(err.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::Internal(format!("JSON error: {}", err))
    }
}

// Make AppError serializable for Tauri
impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let cmd_err = CommandError::from(self.clone());
        cmd_err.serialize(serializer)
    }
}

impl Clone for AppError {
    fn clone(&self) -> Self {
        match self {
            AppError::Auth(s) => AppError::Auth(s.clone()),
            AppError::Crypto(s) => AppError::Crypto(s.clone()),
            AppError::Storage(s) => AppError::Storage(s.clone()),
            AppError::Network(s) => AppError::Network(s.clone()),
            AppError::File(s) => AppError::File(s.clone()),
            AppError::Validation(s) => AppError::Validation(s.clone()),
            AppError::NotFound(s) => AppError::NotFound(s.clone()),
            AppError::PermissionDenied(s) => AppError::PermissionDenied(s.clone()),
            AppError::Internal(s) => AppError::Internal(s.clone()),
            AppError::NotAuthenticated => AppError::NotAuthenticated,
            AppError::SessionExpired => AppError::SessionExpired,
            AppError::Keyring(s) => AppError::Keyring(s.clone()),
            AppError::Database(s) => AppError::Database(s.clone()),
        }
    }
}
