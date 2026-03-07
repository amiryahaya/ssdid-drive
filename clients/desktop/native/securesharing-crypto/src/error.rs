//! Error types for cryptographic operations

use thiserror::Error;

/// Result type for crypto operations
pub type CryptoResult<T> = Result<T, CryptoError>;

/// Cryptographic error types
#[derive(Error, Debug, Clone)]
pub enum CryptoError {
    #[error("Invalid parameter: {0}")]
    InvalidParam(String),

    #[error("Random number generation failed")]
    RngFailed,

    #[error("Memory allocation failed")]
    MemoryError,

    #[error("OpenSSL error")]
    OpenSslError,

    #[error("Message too large for modulus")]
    MessageTooLarge,

    #[error("Library not initialized")]
    NotInitialized,

    #[error("Invalid security level: {0}")]
    InvalidLevel(i32),

    #[error("Signature verification failed")]
    VerificationFailed,

    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),

    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),

    #[error("Key derivation failed: {0}")]
    KeyDerivationFailed(String),

    #[error("Invalid key size: expected {expected}, got {actual}")]
    InvalidKeySize { expected: usize, actual: usize },

    #[error("Unknown error: {0}")]
    Unknown(String),
}

impl From<i32> for CryptoError {
    fn from(code: i32) -> Self {
        match code {
            -1 => CryptoError::InvalidParam("Invalid parameter".to_string()),
            -2 => CryptoError::RngFailed,
            -3 => CryptoError::MemoryError,
            -4 => CryptoError::OpenSslError,
            -5 => CryptoError::MessageTooLarge,
            -6 => CryptoError::NotInitialized,
            -7 => CryptoError::InvalidLevel(code),
            _ => CryptoError::Unknown(format!("Error code: {}", code)),
        }
    }
}
