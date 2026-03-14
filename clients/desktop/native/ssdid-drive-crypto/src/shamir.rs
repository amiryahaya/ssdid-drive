//! Shamir's Secret Sharing Scheme
//!
//! Implements threshold secret sharing over GF(2^8) for splitting
//! cryptographic keys among trustees for recovery purposes.

use crate::error::{CryptoError, CryptoResult};
use rand::RngCore;
use zeroize::{Zeroize, Zeroizing, ZeroizeOnDrop};

/// A share of a secret
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Share {
    /// Share index (1-255, 0 is reserved for secret)
    pub x: u8,
    /// Share data
    pub y: Vec<u8>,
}

impl Share {
    /// Encode share to bytes: x || y
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(1 + self.y.len());
        bytes.push(self.x);
        bytes.extend_from_slice(&self.y);
        bytes
    }

    /// Decode share from bytes
    pub fn from_bytes(bytes: &[u8]) -> CryptoResult<Self> {
        if bytes.len() < 2 {
            return Err(CryptoError::InvalidParam("Share too short".into()));
        }
        Ok(Share {
            x: bytes[0],
            y: bytes[1..].to_vec(),
        })
    }
}

/// GF(2^8) arithmetic using AES polynomial x^8 + x^4 + x^3 + x + 1
mod gf256 {
    /// Multiplication in GF(2^8)
    pub fn mul(a: u8, b: u8) -> u8 {
        let mut result: u8 = 0;
        let mut a = a;
        let mut b = b;

        while b != 0 {
            if b & 1 != 0 {
                result ^= a;
            }
            let high_bit = a & 0x80;
            a <<= 1;
            if high_bit != 0 {
                a ^= 0x1b; // AES irreducible polynomial
            }
            b >>= 1;
        }
        result
    }

    /// Find multiplicative inverse in GF(2^8) using extended Euclidean algorithm
    pub fn inv(a: u8) -> u8 {
        if a == 0 {
            return 0; // 0 has no inverse
        }
        // Use exponentiation: a^254 = a^(-1) in GF(2^8)
        let mut result = a;
        for _ in 0..6 {
            result = mul(result, result);
            result = mul(result, a);
        }
        mul(result, result)
    }

    /// Division in GF(2^8)
    pub fn div(a: u8, b: u8) -> u8 {
        mul(a, inv(b))
    }
}

/// Split a secret into n shares with threshold k
///
/// # Arguments
/// * `secret` - The secret to split (any length)
/// * `k` - Threshold (minimum shares needed to reconstruct)
/// * `n` - Total number of shares to generate
///
/// # Returns
/// Vector of n shares
pub fn split(secret: &[u8], k: u8, n: u8) -> CryptoResult<Vec<Share>> {
    if k < 2 {
        return Err(CryptoError::InvalidParam(
            "Threshold must be at least 2".into(),
        ));
    }
    if n < k {
        return Err(CryptoError::InvalidParam(
            "Number of shares must be >= threshold".into(),
        ));
    }
    if n > 254 {
        return Err(CryptoError::InvalidParam(
            "Maximum 254 shares supported".into(),
        ));
    }
    if secret.is_empty() {
        return Err(CryptoError::InvalidParam("Secret cannot be empty".into()));
    }

    let mut rng = rand::thread_rng();
    let secret_len = secret.len();

    // Generate random coefficients for each polynomial (one per byte)
    // For each byte position, we have a polynomial of degree k-1
    // where the constant term is the secret byte
    let mut coefficients: Vec<Vec<u8>> = Vec::with_capacity(secret_len);
    for i in 0..secret_len {
        let mut coefs = vec![0u8; k as usize];
        coefs[0] = secret[i]; // constant term is the secret byte
        rng.fill_bytes(&mut coefs[1..]); // random coefficients for higher terms
        coefficients.push(coefs);
    }

    // Generate shares
    let mut shares = Vec::with_capacity(n as usize);
    for i in 1..=n {
        let x = i;
        let mut y = Vec::with_capacity(secret_len);

        for coefs in &coefficients {
            // Evaluate polynomial at x using Horner's method
            let mut value = coefs[(k - 1) as usize];
            for j in (0..(k - 1) as usize).rev() {
                value = gf256::mul(value, x);
                value ^= coefs[j];
            }
            y.push(value);
        }

        shares.push(Share { x, y });
    }

    // Zeroize coefficients
    for mut coefs in coefficients {
        coefs.zeroize();
    }

    Ok(shares)
}

/// Reconstruct the secret from k or more shares using Lagrange interpolation
///
/// # Arguments
/// * `shares` - At least k shares from the original split
///
/// # Returns
/// The reconstructed secret
pub fn combine(shares: &[Share]) -> CryptoResult<Zeroizing<Vec<u8>>> {
    if shares.is_empty() {
        return Err(CryptoError::InvalidParam("No shares provided".into()));
    }

    let k = shares.len();
    let secret_len = shares[0].y.len();

    // Verify all shares have same length
    for share in shares {
        if share.y.len() != secret_len {
            return Err(CryptoError::InvalidParam(
                "Shares have inconsistent lengths".into(),
            ));
        }
        if share.x == 0 {
            return Err(CryptoError::InvalidParam(
                "Invalid share index 0".into(),
            ));
        }
    }

    // Check for duplicate x values
    let mut seen = [false; 256];
    for share in shares {
        if seen[share.x as usize] {
            return Err(CryptoError::InvalidParam(
                "Duplicate share indices".into(),
            ));
        }
        seen[share.x as usize] = true;
    }

    // Reconstruct each byte using Lagrange interpolation at x=0
    let mut secret = Vec::with_capacity(secret_len);

    for byte_idx in 0..secret_len {
        let mut value: u8 = 0;

        // For each share, compute Lagrange basis polynomial at x=0
        for i in 0..k {
            let xi = shares[i].x;
            let yi = shares[i].y[byte_idx];

            // Compute Lagrange basis: product of (0 - xj) / (xi - xj) for j != i
            // At x=0: product of xj / (xj - xi) for j != i (using xj since (0-xj) = xj in GF)
            let mut basis: u8 = 1;
            for j in 0..k {
                if i != j {
                    let xj = shares[j].x;
                    // basis *= xj / (xj ^ xi) (^ is XOR which is subtraction in GF(2^8))
                    basis = gf256::mul(basis, gf256::div(xj, xj ^ xi));
                }
            }

            value ^= gf256::mul(yi, basis);
        }

        secret.push(value);
    }

    Ok(Zeroizing::new(secret))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_and_combine_exact_threshold() {
        let secret = b"test secret key 12345678901234567890";
        let k = 3;
        let n = 5;

        let shares = split(secret, k, n).unwrap();
        assert_eq!(shares.len(), n as usize);

        // Use exactly k shares
        let subset: Vec<Share> = shares.into_iter().take(k as usize).collect();
        let recovered = combine(&subset).unwrap();

        assert_eq!(recovered, secret);
    }

    #[test]
    fn test_split_and_combine_more_than_threshold() {
        let secret = b"another secret";
        let k = 2;
        let n = 4;

        let shares = split(secret, k, n).unwrap();

        // Use all shares (more than threshold)
        let recovered = combine(&shares).unwrap();
        assert_eq!(recovered, secret);
    }

    #[test]
    fn test_split_and_combine_different_subsets() {
        let secret = b"secret data";
        let k = 3;
        let n = 5;

        let shares = split(secret, k, n).unwrap();

        // Try different combinations
        let subset1 = vec![shares[0].clone(), shares[1].clone(), shares[2].clone()];
        let subset2 = vec![shares[0].clone(), shares[2].clone(), shares[4].clone()];
        let subset3 = vec![shares[1].clone(), shares[3].clone(), shares[4].clone()];

        assert_eq!(combine(&subset1).unwrap(), secret);
        assert_eq!(combine(&subset2).unwrap(), secret);
        assert_eq!(combine(&subset3).unwrap(), secret);
    }

    #[test]
    fn test_insufficient_shares() {
        let secret = b"secret";
        let k = 3;
        let n = 5;

        let shares = split(secret, k, n).unwrap();

        // Try with fewer than k shares (should produce wrong result)
        let subset: Vec<Share> = shares.into_iter().take(2).collect();
        let recovered = combine(&subset).unwrap();

        // Should NOT match (with overwhelming probability)
        assert_ne!(recovered, secret);
    }

    #[test]
    fn test_share_serialization() {
        let share = Share {
            x: 42,
            y: vec![1, 2, 3, 4, 5],
        };

        let bytes = share.to_bytes();
        let recovered = Share::from_bytes(&bytes).unwrap();

        assert_eq!(recovered.x, share.x);
        assert_eq!(recovered.y, share.y);
    }

    #[test]
    fn test_32_byte_key() {
        // Test with typical AES-256 key size
        let secret = vec![0xAB; 32];
        let k = 3;
        let n = 5;

        let shares = split(&secret, k, n).unwrap();
        let subset: Vec<Share> = shares.into_iter().take(k as usize).collect();
        let recovered = combine(&subset).unwrap();

        assert_eq!(recovered, secret);
    }
}
