//! SSDID Drive Cryptographic Library
//!
//! Provides safe Rust wrappers for post-quantum cryptographic operations:
//!
//! - **KAZ-KEM**: Post-quantum key encapsulation mechanism
//! - **KAZ-SIGN**: Post-quantum digital signatures
//! - **ML-KEM**: NIST-standard key encapsulation (formerly CRYSTALS-Kyber)
//! - **ML-DSA**: NIST-standard digital signatures (formerly CRYSTALS-Dilithium)
//! - **AES-256-GCM**: Symmetric encryption
//! - **Argon2id**: Password-based key derivation
//! - **HKDF**: Key derivation function

pub mod error;
pub mod kaz_kem;
pub mod kaz_sign;
pub mod ml_kem;
pub mod ml_dsa;
pub mod shamir;
pub mod symmetric;

pub use error::{CryptoError, CryptoResult};

/// Initialize all cryptographic subsystems
///
/// Must be called before using any crypto functions.
pub fn init() -> CryptoResult<()> {
    kaz_kem::init(kaz_kem::SecurityLevel::Level256)?;
    kaz_sign::init()?;
    Ok(())
}

/// Clean up all cryptographic subsystems
///
/// Should be called at application exit.
pub fn cleanup() {
    kaz_kem::cleanup();
    kaz_sign::cleanup();
}
