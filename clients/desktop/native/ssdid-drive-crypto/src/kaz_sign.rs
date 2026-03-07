//! Safe wrapper for KAZ-SIGN post-quantum digital signatures

use crate::error::{CryptoError, CryptoResult};
use std::sync::OnceLock;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Thread-safe initialization state using OnceLock instead of static mut
static INIT_RESULT: OnceLock<Result<(), CryptoError>> = OnceLock::new();

/// KAZ-SIGN security levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum SecurityLevel {
    Level128 = 128,
    Level192 = 192,
    Level256 = 256,
}

/// KAZ-SIGN signing key pair with automatic zeroization
#[derive(ZeroizeOnDrop)]
pub struct KeyPair {
    #[zeroize(skip)]
    pub public_key: Vec<u8>,
    secret_key: Vec<u8>,
}

impl KeyPair {
    /// Get the secret key bytes
    pub fn secret_key(&self) -> &[u8] {
        &self.secret_key
    }
}

/// Initialize KAZ-SIGN random state
pub fn init() -> CryptoResult<()> {
    let result = INIT_RESULT.get_or_init(|| {
        let code = unsafe { kaz_sign_sys::kaz_sign_init_random() };
        if code != 0 {
            Err(CryptoError::from(code))
        } else {
            Ok(())
        }
    });

    result.clone()
}

/// Check if KAZ-SIGN is initialized
pub fn is_initialized() -> bool {
    unsafe { kaz_sign_sys::kaz_sign_is_initialized() == 1 }
}

/// Get key sizes for a security level
pub fn get_key_sizes(level: SecurityLevel) -> CryptoResult<(usize, usize)> {
    unsafe {
        let params = kaz_sign_sys::kaz_sign_get_level_params(level as i32);
        if params.is_null() {
            return Err(CryptoError::InvalidLevel(level as i32));
        }
        let params = &*params;
        Ok((params.public_key_bytes, params.secret_key_bytes))
    }
}

/// Get signature overhead for a security level
pub fn get_signature_overhead(level: SecurityLevel) -> CryptoResult<usize> {
    unsafe {
        let params = kaz_sign_sys::kaz_sign_get_level_params(level as i32);
        if params.is_null() {
            return Err(CryptoError::InvalidLevel(level as i32));
        }
        Ok((*params).signature_overhead)
    }
}

/// Generate a KAZ-SIGN key pair for specified security level
pub fn generate_keypair(level: SecurityLevel) -> CryptoResult<KeyPair> {
    if !is_initialized() {
        init()?;
    }

    let (pk_size, sk_size) = get_key_sizes(level)?;

    let mut public_key = vec![0u8; pk_size];
    let mut secret_key = vec![0u8; sk_size];

    let result = unsafe {
        kaz_sign_sys::kaz_sign_keypair_ex(
            level as i32,
            public_key.as_mut_ptr(),
            secret_key.as_mut_ptr(),
        )
    };

    if result != 0 {
        secret_key.zeroize();
        return Err(CryptoError::from(result));
    }

    Ok(KeyPair {
        public_key,
        secret_key,
    })
}

/// Sign a message with the secret key
pub fn sign(message: &[u8], secret_key: &[u8], level: SecurityLevel) -> CryptoResult<Vec<u8>> {
    if !is_initialized() {
        init()?;
    }

    let overhead = get_signature_overhead(level)?;
    let max_sig_len = overhead + message.len();

    let mut signature = vec![0u8; max_sig_len];
    let mut sig_len: u64 = 0;

    let result = unsafe {
        kaz_sign_sys::kaz_sign_signature_ex(
            level as i32,
            signature.as_mut_ptr(),
            &mut sig_len,
            message.as_ptr(),
            message.len() as u64,
            secret_key.as_ptr(),
        )
    };

    if result != 0 {
        return Err(CryptoError::from(result));
    }

    signature.truncate(sig_len as usize);
    Ok(signature)
}

/// Verify a signature and extract the message
pub fn verify(
    signature: &[u8],
    public_key: &[u8],
    level: SecurityLevel,
) -> CryptoResult<Vec<u8>> {
    if !is_initialized() {
        init()?;
    }

    let overhead = get_signature_overhead(level)?;
    let max_msg_len = signature.len().saturating_sub(overhead);

    let mut message = vec![0u8; max_msg_len];
    let mut msg_len: u64 = 0;

    let result = unsafe {
        kaz_sign_sys::kaz_sign_verify_ex(
            level as i32,
            message.as_mut_ptr(),
            &mut msg_len,
            signature.as_ptr(),
            signature.len() as u64,
            public_key.as_ptr(),
        )
    };

    if result != 0 {
        if result == kaz_sign_sys::KAZ_SIGN_ERROR_VERIFY {
            return Err(CryptoError::VerificationFailed);
        }
        return Err(CryptoError::from(result));
    }

    message.truncate(msg_len as usize);
    Ok(message)
}

/// Clean up KAZ-SIGN state
pub fn cleanup() {
    unsafe {
        kaz_sign_sys::kaz_sign_clear_all();
        kaz_sign_sys::kaz_sign_clear_random();
    }
}

/// Get KAZ-SIGN version string
pub fn version() -> String {
    unsafe {
        let ptr = kaz_sign_sys::kaz_sign_version();
        if ptr.is_null() {
            return String::new();
        }
        std::ffi::CStr::from_ptr(ptr)
            .to_string_lossy()
            .into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keypair_and_signature() {
        init().unwrap();

        let keypair = generate_keypair(SecurityLevel::Level256).unwrap();
        assert!(!keypair.public_key.is_empty());
        assert!(!keypair.secret_key().is_empty());

        let message = b"Hello, SSDID Drive!";
        let signature = sign(message, keypair.secret_key(), SecurityLevel::Level256).unwrap();
        assert!(!signature.is_empty());

        let recovered = verify(&signature, &keypair.public_key, SecurityLevel::Level256).unwrap();
        assert_eq!(message.as_slice(), recovered.as_slice());

        cleanup();
    }
}
