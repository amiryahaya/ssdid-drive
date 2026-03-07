//! ML-KEM (NIST FIPS 203) key encapsulation
//!
//! Provides ML-KEM-768 for NIST-standard post-quantum key encapsulation.

use crate::error::{CryptoError, CryptoResult};
use pqcrypto_mlkem::mlkem768;
use pqcrypto_traits::kem::{Ciphertext, PublicKey, SecretKey, SharedSecret};
use zeroize::ZeroizeOnDrop;

/// ML-KEM-768 public key size
pub const PUBLIC_KEY_SIZE: usize = 1184;

/// ML-KEM-768 secret key size
pub const SECRET_KEY_SIZE: usize = 2400;

/// ML-KEM-768 ciphertext size
pub const CIPHERTEXT_SIZE: usize = 1088;

/// ML-KEM-768 shared secret size
pub const SHARED_SECRET_SIZE: usize = 32;

/// ML-KEM key pair
#[derive(ZeroizeOnDrop)]
pub struct KeyPair {
    #[zeroize(skip)]
    pub public_key: Vec<u8>,
    pub secret_key: Vec<u8>,
}

/// ML-KEM encapsulation result
#[derive(ZeroizeOnDrop)]
pub struct Encapsulation {
    #[zeroize(skip)]
    pub ciphertext: Vec<u8>,
    pub shared_secret: Vec<u8>,
}

/// Generate ML-KEM-768 key pair
pub fn generate_keypair() -> CryptoResult<KeyPair> {
    let (pk, sk) = mlkem768::keypair();

    Ok(KeyPair {
        public_key: pk.as_bytes().to_vec(),
        secret_key: sk.as_bytes().to_vec(),
    })
}

/// Encapsulate shared secret using ML-KEM-768
pub fn encapsulate(public_key: &[u8]) -> CryptoResult<Encapsulation> {
    if public_key.len() != PUBLIC_KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: PUBLIC_KEY_SIZE,
            actual: public_key.len(),
        });
    }

    let pk = mlkem768::PublicKey::from_bytes(public_key)
        .map_err(|e| CryptoError::Unknown(format!("Invalid public key: {:?}", e)))?;

    let (ss, ct) = mlkem768::encapsulate(&pk);

    Ok(Encapsulation {
        ciphertext: ct.as_bytes().to_vec(),
        shared_secret: ss.as_bytes().to_vec(),
    })
}

/// Decapsulate ciphertext using ML-KEM-768
pub fn decapsulate(ciphertext: &[u8], secret_key: &[u8]) -> CryptoResult<Vec<u8>> {
    if ciphertext.len() != CIPHERTEXT_SIZE {
        return Err(CryptoError::Unknown(format!(
            "Invalid ciphertext size: expected {}, got {}",
            CIPHERTEXT_SIZE,
            ciphertext.len()
        )));
    }

    if secret_key.len() != SECRET_KEY_SIZE {
        return Err(CryptoError::InvalidKeySize {
            expected: SECRET_KEY_SIZE,
            actual: secret_key.len(),
        });
    }

    let sk = mlkem768::SecretKey::from_bytes(secret_key)
        .map_err(|e| CryptoError::Unknown(format!("Invalid secret key: {:?}", e)))?;

    let ct = mlkem768::Ciphertext::from_bytes(ciphertext)
        .map_err(|e| CryptoError::Unknown(format!("Invalid ciphertext: {:?}", e)))?;

    let ss = mlkem768::decapsulate(&ct, &sk);

    Ok(ss.as_bytes().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ml_kem_roundtrip() {
        let keypair = generate_keypair().unwrap();
        let encap = encapsulate(&keypair.public_key).unwrap();
        let decap_ss = decapsulate(&encap.ciphertext, &keypair.secret_key).unwrap();

        assert_eq!(encap.shared_secret, decap_ss);
    }
}
