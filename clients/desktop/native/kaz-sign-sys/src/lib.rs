//! Low-level FFI bindings for KAZ-SIGN
//!
//! This crate provides raw, unsafe bindings to the KAZ-SIGN C library.
//! For safe Rust wrappers, use the `ssdid-drive-crypto` crate.

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(dead_code)]

use libc::{c_char, c_int, c_uchar, c_ulonglong, size_t};

// Error codes
pub const KAZ_SIGN_SUCCESS: c_int = 0;
pub const KAZ_SIGN_ERROR_MEMORY: c_int = -1;
pub const KAZ_SIGN_ERROR_RNG: c_int = -2;
pub const KAZ_SIGN_ERROR_INVALID: c_int = -3;
pub const KAZ_SIGN_ERROR_VERIFY: c_int = -4;

// Security levels
pub const KAZ_LEVEL_128: c_int = 128;
pub const KAZ_LEVEL_192: c_int = 192;
pub const KAZ_LEVEL_256: c_int = 256;

// Key and signature sizes for level 256
pub const KAZ_SIGN_SECRETKEYBYTES_256: size_t = 64;
pub const KAZ_SIGN_PUBLICKEYBYTES_256: size_t = 118;
pub const KAZ_SIGN_BYTES_256: size_t = 64;
pub const KAZ_SIGN_S1BYTES_256: size_t = 118;
pub const KAZ_SIGN_S2BYTES_256: size_t = 119;
pub const KAZ_SIGN_S3BYTES_256: size_t = 119;
pub const KAZ_SIGN_SIGNATURE_OVERHEAD_256: size_t = 356; // S1 + S2 + S3

/// Security level parameters structure
#[repr(C)]
#[derive(Debug, Clone)]
pub struct kaz_sign_level_params_t {
    pub level: c_int,
    pub algorithm_name: *const c_char,
    pub secret_key_bytes: size_t,
    pub public_key_bytes: size_t,
    pub hash_bytes: size_t,
    pub signature_overhead: size_t,
    pub s_bytes: size_t,
    pub t_bytes: size_t,
    pub s1_bytes: size_t,
    pub s2_bytes: size_t,
    pub s3_bytes: size_t,
}

extern "C" {
    // Random state management

    /// Initialize the global random state with proper entropy.
    /// Must be called before any signing operations.
    pub fn kaz_sign_init_random() -> c_int;

    /// Clear and free the global random state.
    pub fn kaz_sign_clear_random();

    /// Check if random state has been initialized.
    pub fn kaz_sign_is_initialized() -> c_int;

    // Core API (compile-time security level)

    /// Generate a KAZ-SIGN key pair.
    pub fn kaz_sign_keypair(pk: *mut c_uchar, sk: *mut c_uchar) -> c_int;

    /// Sign a message.
    pub fn kaz_sign_signature(
        sig: *mut c_uchar,
        siglen: *mut c_ulonglong,
        msg: *const c_uchar,
        msglen: c_ulonglong,
        sk: *const c_uchar,
    ) -> c_int;

    /// Verify a signature and extract the message.
    pub fn kaz_sign_verify(
        msg: *mut c_uchar,
        msglen: *mut c_ulonglong,
        sig: *const c_uchar,
        siglen: c_ulonglong,
        pk: *const c_uchar,
    ) -> c_int;

    /// Hash a message using the appropriate hash function.
    pub fn kaz_sign_hash(
        msg: *const c_uchar,
        msglen: c_ulonglong,
        hash: *mut c_uchar,
    ) -> c_int;

    // Version API

    /// Get the version string.
    pub fn kaz_sign_version() -> *const c_char;

    /// Get the version number as integer.
    pub fn kaz_sign_version_number() -> c_int;

    // Runtime security level API

    /// Get parameters for a security level.
    pub fn kaz_sign_get_level_params(level: c_int) -> *const kaz_sign_level_params_t;

    /// Initialize the library for a specific security level.
    pub fn kaz_sign_init_level(level: c_int) -> c_int;

    /// Clear resources for a specific security level.
    pub fn kaz_sign_clear_level(level: c_int);

    /// Clear resources for all security levels.
    pub fn kaz_sign_clear_all();

    /// Generate a key pair for a specific security level.
    pub fn kaz_sign_keypair_ex(
        level: c_int,
        pk: *mut c_uchar,
        sk: *mut c_uchar,
    ) -> c_int;

    /// Sign a message with a specific security level.
    pub fn kaz_sign_signature_ex(
        level: c_int,
        sig: *mut c_uchar,
        siglen: *mut c_ulonglong,
        msg: *const c_uchar,
        msglen: c_ulonglong,
        sk: *const c_uchar,
    ) -> c_int;

    /// Verify a signature with a specific security level.
    pub fn kaz_sign_verify_ex(
        level: c_int,
        msg: *mut c_uchar,
        msglen: *mut c_ulonglong,
        sig: *const c_uchar,
        siglen: c_ulonglong,
        pk: *const c_uchar,
    ) -> c_int;

    /// Hash a message with the hash function for a specific security level.
    pub fn kaz_sign_hash_ex(
        level: c_int,
        msg: *const c_uchar,
        msglen: c_ulonglong,
        hash: *mut c_uchar,
    ) -> c_int;
}

// KDF functions
extern "C" {
    /// HKDF-Extract.
    pub fn kaz_hkdf_extract(
        salt: *const c_uchar,
        salt_len: size_t,
        ikm: *const c_uchar,
        ikm_len: size_t,
        prk: *mut c_uchar,
        prk_len: *mut size_t,
    ) -> c_int;

    /// HKDF-Expand.
    pub fn kaz_hkdf_expand(
        prk: *const c_uchar,
        prk_len: size_t,
        info: *const c_uchar,
        info_len: size_t,
        okm: *mut c_uchar,
        okm_len: size_t,
    ) -> c_int;

    /// HKDF combined Extract-and-Expand.
    pub fn kaz_hkdf(
        salt: *const c_uchar,
        salt_len: size_t,
        ikm: *const c_uchar,
        ikm_len: size_t,
        info: *const c_uchar,
        info_len: size_t,
        okm: *mut c_uchar,
        okm_len: size_t,
    ) -> c_int;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_init_and_cleanup() {
        unsafe {
            let result = kaz_sign_init_random();
            assert_eq!(result, KAZ_SIGN_SUCCESS);
            assert_eq!(kaz_sign_is_initialized(), 1);
            kaz_sign_clear_random();
        }
    }

    #[test]
    fn test_level_params() {
        unsafe {
            let params = kaz_sign_get_level_params(KAZ_LEVEL_256);
            assert!(!params.is_null());
            let params = &*params;
            assert_eq!(params.level, KAZ_LEVEL_256);
            assert!(params.secret_key_bytes > 0);
            assert!(params.public_key_bytes > 0);
        }
    }
}
