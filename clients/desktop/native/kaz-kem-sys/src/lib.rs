//! Low-level FFI bindings for KAZ-KEM
//!
//! This crate provides raw, unsafe bindings to the KAZ-KEM C library.
//! For safe Rust wrappers, use the `securesharing-crypto` crate.
//!
//! # Safety
//!
//! All functions in this crate are unsafe and follow C conventions.
//! Callers must ensure:
//! - Buffers are properly sized
//! - KAZ-KEM is initialized before use
//! - Proper cleanup is called on exit

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(dead_code)]

use libc::{c_char, c_int, c_uchar, c_ulonglong, size_t};

// Error codes
pub const KAZ_KEM_SUCCESS: c_int = 0;
pub const KAZ_KEM_ERROR_INVALID_PARAM: c_int = -1;
pub const KAZ_KEM_ERROR_RNG: c_int = -2;
pub const KAZ_KEM_ERROR_MEMORY: c_int = -3;
pub const KAZ_KEM_ERROR_OPENSSL: c_int = -4;
pub const KAZ_KEM_ERROR_MSG_TOO_LARGE: c_int = -5;
pub const KAZ_KEM_ERROR_NOT_INIT: c_int = -6;
pub const KAZ_KEM_ERROR_INVALID_LEVEL: c_int = -7;

// Security levels
pub const KAZ_KEM_LEVEL_128: c_int = 128;
pub const KAZ_KEM_LEVEL_192: c_int = 192;
pub const KAZ_KEM_LEVEL_256: c_int = 256;

extern "C" {
    /// Initialize KAZ-KEM with specified security level.
    /// Must be called before any other KEM operations.
    ///
    /// # Arguments
    /// * `level` - Security level (128, 192, or 256)
    ///
    /// # Returns
    /// 0 on success, negative error code on failure
    pub fn kaz_kem_init(level: c_int) -> c_int;

    /// Get the current security level.
    ///
    /// # Returns
    /// Current security level (128, 192, or 256), or 0 if not initialized
    pub fn kaz_kem_get_level() -> c_int;

    /// Check if KAZ-KEM is initialized.
    ///
    /// # Returns
    /// 1 if initialized, 0 otherwise
    pub fn kaz_kem_is_initialized() -> c_int;

    /// Get public key size in bytes.
    pub fn kaz_kem_publickey_bytes() -> size_t;

    /// Get private key size in bytes.
    pub fn kaz_kem_privatekey_bytes() -> size_t;

    /// Get ciphertext size in bytes.
    pub fn kaz_kem_ciphertext_bytes() -> size_t;

    /// Get shared secret size in bytes.
    pub fn kaz_kem_shared_secret_bytes() -> size_t;

    /// Generate a KEM key pair.
    ///
    /// # Arguments
    /// * `pk` - Output buffer for public key (kaz_kem_publickey_bytes())
    /// * `sk` - Output buffer for private key (kaz_kem_privatekey_bytes())
    ///
    /// # Returns
    /// 0 on success, negative error code on failure
    pub fn kaz_kem_keypair(pk: *mut c_uchar, sk: *mut c_uchar) -> c_int;

    /// Encapsulate a shared secret.
    ///
    /// # Arguments
    /// * `ct` - Output buffer for ciphertext
    /// * `ctlen` - Output: length of ciphertext
    /// * `ss` - Input shared secret (must be < modulus N)
    /// * `sslen` - Length of shared secret
    /// * `pk` - Public key from kaz_kem_keypair
    ///
    /// # Returns
    /// 0 on success, negative error code on failure
    pub fn kaz_kem_encapsulate(
        ct: *mut c_uchar,
        ctlen: *mut c_ulonglong,
        ss: *const c_uchar,
        sslen: c_ulonglong,
        pk: *const c_uchar,
    ) -> c_int;

    /// Decapsulate to recover the shared secret.
    ///
    /// # Arguments
    /// * `ss` - Output buffer for shared secret
    /// * `sslen` - Output: length of shared secret
    /// * `ct` - Ciphertext from kaz_kem_encapsulate
    /// * `ctlen` - Length of ciphertext
    /// * `sk` - Private key from kaz_kem_keypair
    ///
    /// # Returns
    /// 0 on success, negative error code on failure
    pub fn kaz_kem_decapsulate(
        ss: *mut c_uchar,
        sslen: *mut c_ulonglong,
        ct: *const c_uchar,
        ctlen: c_ulonglong,
        sk: *const c_uchar,
    ) -> c_int;

    /// Cleanup KEM state and securely clear sensitive data.
    pub fn kaz_kem_cleanup();

    /// Full cleanup including OpenSSL internal state.
    /// Call only at final program exit.
    pub fn kaz_kem_cleanup_full();

    /// Get version string.
    pub fn kaz_kem_version() -> *const c_char;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_init_and_cleanup() {
        unsafe {
            let result = kaz_kem_init(KAZ_KEM_LEVEL_256);
            assert_eq!(result, KAZ_KEM_SUCCESS);
            assert_eq!(kaz_kem_is_initialized(), 1);
            assert_eq!(kaz_kem_get_level(), KAZ_KEM_LEVEL_256);
            kaz_kem_cleanup();
        }
    }

    #[test]
    fn test_key_sizes() {
        unsafe {
            let result = kaz_kem_init(KAZ_KEM_LEVEL_256);
            assert_eq!(result, KAZ_KEM_SUCCESS);

            let pk_size = kaz_kem_publickey_bytes();
            let sk_size = kaz_kem_privatekey_bytes();
            let ct_size = kaz_kem_ciphertext_bytes();
            let ss_size = kaz_kem_shared_secret_bytes();

            assert!(pk_size > 0);
            assert!(sk_size > 0);
            assert!(ct_size > 0);
            assert!(ss_size > 0);

            kaz_kem_cleanup();
        }
    }
}
