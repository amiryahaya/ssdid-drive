//! ML-DSA (NIST FIPS 204) digital signatures
//!
//! Provides ML-DSA-65 for NIST-standard post-quantum signatures.

use crate::error::{CryptoError, CryptoResult};
use pqcrypto_mldsa::mldsa65;
use pqcrypto_traits::sign::{DetachedSignature, PublicKey, SecretKey};
use zeroize::ZeroizeOnDrop;

/// ML-DSA-65 public key size
pub const PUBLIC_KEY_SIZE: usize = 1952;

/// ML-DSA-65 secret key size
pub const SECRET_KEY_SIZE: usize = 4032;

/// ML-DSA-65 signature size
pub const SIGNATURE_SIZE: usize = 3309;

/// ML-DSA signing key pair
#[derive(ZeroizeOnDrop)]
pub struct KeyPair {
    #[zeroize(skip)]
    pub public_key: Vec<u8>,
    pub secret_key: Vec<u8>,
}

/// Generate ML-DSA-65 key pair
pub fn generate_keypair() -> CryptoResult<KeyPair> {
    let (pk, sk) = mldsa65::keypair();

    Ok(KeyPair {
        public_key: pk.as_bytes().to_vec(),
        secret_key: sk.as_bytes().to_vec(),
    })
}

/// Sign a message using ML-DSA-65
pub fn sign(message: &[u8], secret_key: &[u8]) -> CryptoResult<Vec<u8>> {
    if secret_key.len() != SECRET_KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: SECRET_KEY_SIZE,
            actual: secret_key.len(),
        });
    }

    let sk = mldsa65::SecretKey::from_bytes(secret_key)
        .map_err(|e| CryptoError::Unknown(format!("Invalid secret key: {:?}", e)))?;

    let sig = mldsa65::detached_sign(message, &sk);

    Ok(sig.as_bytes().to_vec())
}

/// Verify a signature using ML-DSA-65
pub fn verify(message: &[u8], signature: &[u8], public_key: &[u8]) -> CryptoResult<bool> {
    if public_key.len() != PUBLIC_KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: PUBLIC_KEY_SIZE,
            actual: public_key.len(),
        });
    }

    if signature.len() != SIGNATURE_SIZE {
        return Err(CryptoError::Unknown(format!(
            "Invalid signature size: expected {}, got {}",
            SIGNATURE_SIZE,
            signature.len()
        )));
    }

    let pk = mldsa65::PublicKey::from_bytes(public_key)
        .map_err(|e| CryptoError::Unknown(format!("Invalid public key: {:?}", e)))?;

    let sig = mldsa65::DetachedSignature::from_bytes(signature)
        .map_err(|e| CryptoError::Unknown(format!("Invalid signature: {:?}", e)))?;

    Ok(mldsa65::verify_detached_signature(&sig, message, &pk).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ml_dsa_roundtrip() {
        let keypair = generate_keypair().unwrap();
        let message = b"Hello, post-quantum world!";

        let sig = sign(message, &keypair.secret_key).unwrap();
        let valid = verify(message, &sig, &keypair.public_key).unwrap();

        assert!(valid);
    }

    #[test]
    fn test_ml_dsa_invalid_signature() {
        let keypair = generate_keypair().unwrap();
        let message = b"Original message";
        let wrong_message = b"Wrong message";

        let sig = sign(message, &keypair.secret_key).unwrap();
        let valid = verify(wrong_message, &sig, &keypair.public_key).unwrap();

        assert!(!valid);
    }
}
