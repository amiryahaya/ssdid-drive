//! Safe wrapper for KAZ-KEM post-quantum key encapsulation

use crate::error::{CryptoError, CryptoResult};
use std::sync::OnceLock;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Thread-safe initialization state using OnceLock instead of static mut
static INIT_RESULT: OnceLock<Result<(), CryptoError>> = OnceLock::new();

/// KAZ-KEM security levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum SecurityLevel {
    Level128 = 128,
    Level192 = 192,
    Level256 = 256,
}

/// KAZ-KEM key pair with automatic zeroization
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

/// KAZ-KEM encapsulation result
#[derive(ZeroizeOnDrop)]
pub struct Encapsulation {
    #[zeroize(skip)]
    pub ciphertext: Vec<u8>,
    pub shared_secret: Vec<u8>,
}

/// Initialize KAZ-KEM with specified security level
pub fn init(level: SecurityLevel) -> CryptoResult<()> {
    let result = INIT_RESULT.get_or_init(|| {
        let code = unsafe { kaz_kem_sys::kaz_kem_init(level as i32) };
        if code != 0 {
            Err(CryptoError::from(code))
        } else {
            Ok(())
        }
    });

    result.clone()
}

/// Check if KAZ-KEM is initialized
pub fn is_initialized() -> bool {
    unsafe { kaz_kem_sys::kaz_kem_is_initialized() == 1 }
}

/// Get public key size in bytes
pub fn public_key_bytes() -> usize {
    unsafe { kaz_kem_sys::kaz_kem_publickey_bytes() }
}

/// Get secret key size in bytes
pub fn secret_key_bytes() -> usize {
    unsafe { kaz_kem_sys::kaz_kem_privatekey_bytes() }
}

/// Get ciphertext size in bytes
pub fn ciphertext_bytes() -> usize {
    unsafe { kaz_kem_sys::kaz_kem_ciphertext_bytes() }
}

/// Get shared secret size in bytes
pub fn shared_secret_bytes() -> usize {
    unsafe { kaz_kem_sys::kaz_kem_shared_secret_bytes() }
}

/// Generate a KAZ-KEM key pair
pub fn generate_keypair() -> CryptoResult<KeyPair> {
    if !is_initialized() {
        return Err(CryptoError::NotInitialized);
    }

    let pk_size = public_key_bytes();
    let sk_size = secret_key_bytes();

    let mut public_key = vec![0u8; pk_size];
    let mut secret_key = vec![0u8; sk_size];

    let result = unsafe {
        kaz_kem_sys::kaz_kem_keypair(
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

/// Encapsulate a random shared secret for a recipient's public key
pub fn encapsulate(public_key: &[u8]) -> CryptoResult<Encapsulation> {
    if !is_initialized() {
        return Err(CryptoError::NotInitialized);
    }

    let expected_pk_size = public_key_bytes();
    if public_key.len() != expected_pk_size {
        return Err(CryptoError::InvalidKeySize {
            expected: expected_pk_size,
            actual: public_key.len(),
        });
    }

    let ct_size = ciphertext_bytes();
    let ss_size = shared_secret_bytes();

    // Generate random shared secret
    let mut shared_secret = vec![0u8; ss_size];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut shared_secret);

    // Mask top bits to ensure value < modulus
    if !shared_secret.is_empty() {
        shared_secret[0] &= 0x1F;
    }

    let mut ciphertext = vec![0u8; ct_size];
    let mut ct_len: u64 = 0;

    let result = unsafe {
        kaz_kem_sys::kaz_kem_encapsulate(
            ciphertext.as_mut_ptr(),
            &mut ct_len,
            shared_secret.as_ptr(),
            shared_secret.len() as u64,
            public_key.as_ptr(),
        )
    };

    if result != 0 {
        shared_secret.zeroize();
        return Err(CryptoError::from(result));
    }

    ciphertext.truncate(ct_len as usize);

    Ok(Encapsulation {
        ciphertext,
        shared_secret,
    })
}

/// Decapsulate ciphertext using secret key to recover shared secret
pub fn decapsulate(ciphertext: &[u8], secret_key: &[u8]) -> CryptoResult<Vec<u8>> {
    if !is_initialized() {
        return Err(CryptoError::NotInitialized);
    }

    let expected_sk_size = secret_key_bytes();
    if secret_key.len() != expected_sk_size {
        return Err(CryptoError::InvalidKeySize {
            expected: expected_sk_size,
            actual: secret_key.len(),
        });
    }

    let ss_size = shared_secret_bytes();
    let mut shared_secret = vec![0u8; ss_size];
    let mut ss_len: u64 = 0;

    let result = unsafe {
        kaz_kem_sys::kaz_kem_decapsulate(
            shared_secret.as_mut_ptr(),
            &mut ss_len,
            ciphertext.as_ptr(),
            ciphertext.len() as u64,
            secret_key.as_ptr(),
        )
    };

    if result != 0 {
        shared_secret.zeroize();
        return Err(CryptoError::from(result));
    }

    shared_secret.truncate(ss_len as usize);
    Ok(shared_secret)
}

/// Clean up KAZ-KEM state
pub fn cleanup() {
    unsafe {
        kaz_kem_sys::kaz_kem_cleanup();
    }
}

/// Get KAZ-KEM version string
pub fn version() -> String {
    unsafe {
        let ptr = kaz_kem_sys::kaz_kem_version();
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
    fn test_keypair_and_encapsulation() {
        init(SecurityLevel::Level256).unwrap();

        let keypair = generate_keypair().unwrap();
        assert!(!keypair.public_key.is_empty());
        assert!(!keypair.secret_key().is_empty());

        let encap = encapsulate(&keypair.public_key).unwrap();
        assert!(!encap.ciphertext.is_empty());
        assert!(!encap.shared_secret.is_empty());

        let decapped = decapsulate(&encap.ciphertext, keypair.secret_key()).unwrap();
        assert_eq!(encap.shared_secret.as_slice(), decapped.as_slice());

        cleanup();
    }
}
