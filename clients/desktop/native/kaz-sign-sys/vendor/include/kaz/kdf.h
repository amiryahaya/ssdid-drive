/*
 * KAZ-SIGN Key Derivation Function (KDF)
 * Version 3.0
 *
 * Implements HKDF (HMAC-based Key Derivation Function) per RFC 5869
 * for secure seed expansion and key derivation.
 *
 * Uses OpenSSL's EVP interface for cryptographic operations.
 */

#ifndef KAZ_KDF_H
#define KAZ_KDF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Constants
 * ============================================================================ */

/* Maximum output length for a single HKDF-Expand call */
#define KAZ_KDF_MAX_OUTPUT_LEN (255 * 32)  /* 255 * hash_len for SHA-256 (internal KDF hash) */

/* Domain separation labels for different key types */
#define KAZ_KDF_LABEL_SECRET_KEY    "KAZ-SIGN-SK"
#define KAZ_KDF_LABEL_PUBLIC_KEY    "KAZ-SIGN-PK"
#define KAZ_KDF_LABEL_SIGNING       "KAZ-SIGN-SIG"
#define KAZ_KDF_LABEL_RANDOM        "KAZ-SIGN-RND"

/* Error codes */
#define KAZ_KDF_SUCCESS             0
#define KAZ_KDF_ERROR_NULL_PTR     -1
#define KAZ_KDF_ERROR_INVALID_LEN  -2
#define KAZ_KDF_ERROR_CRYPTO       -3

/* ============================================================================
 * HKDF Functions (RFC 5869)
 * ============================================================================ */

/**
 * HKDF-Extract: Extract a pseudorandom key from input keying material.
 *
 * PRK = HMAC-Hash(salt, IKM)
 *
 * @param salt      Optional salt value (can be NULL, uses zeros)
 * @param salt_len  Length of salt
 * @param ikm       Input keying material
 * @param ikm_len   Length of IKM
 * @param prk       Output: pseudorandom key (hash_len bytes)
 * @param prk_len   Output: length of PRK written
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_hkdf_extract(const unsigned char *salt, size_t salt_len,
                     const unsigned char *ikm, size_t ikm_len,
                     unsigned char *prk, size_t *prk_len);

/**
 * HKDF-Expand: Expand pseudorandom key into output keying material.
 *
 * OKM = T(1) || T(2) || ... || T(N)
 * where T(i) = HMAC-Hash(PRK, T(i-1) || info || i)
 *
 * @param prk       Pseudorandom key from HKDF-Extract
 * @param prk_len   Length of PRK
 * @param info      Optional context/application-specific info
 * @param info_len  Length of info
 * @param okm       Output: output keying material
 * @param okm_len   Desired length of OKM
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_hkdf_expand(const unsigned char *prk, size_t prk_len,
                    const unsigned char *info, size_t info_len,
                    unsigned char *okm, size_t okm_len);

/**
 * HKDF: Combined Extract-and-Expand operation.
 *
 * Convenience function that performs both steps.
 *
 * @param salt      Optional salt value
 * @param salt_len  Length of salt
 * @param ikm       Input keying material
 * @param ikm_len   Length of IKM
 * @param info      Optional context info
 * @param info_len  Length of info
 * @param okm       Output: output keying material
 * @param okm_len   Desired length of OKM
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_hkdf(const unsigned char *salt, size_t salt_len,
             const unsigned char *ikm, size_t ikm_len,
             const unsigned char *info, size_t info_len,
             unsigned char *okm, size_t okm_len);

/* ============================================================================
 * KAZ-SIGN Specific Key Derivation
 * ============================================================================ */

/**
 * Derive secret key components (s, t) from a seed.
 *
 * Uses HKDF with domain separation to derive the secret key values
 * used in the KAZ-SIGN algorithm.
 *
 * @param seed      Random seed (should be at least 32 bytes)
 * @param seed_len  Length of seed
 * @param s_bytes   Output: s component bytes
 * @param s_len     Length of s output buffer
 * @param t_bytes   Output: t component bytes
 * @param t_len     Length of t output buffer
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_kdf_derive_secret_key(const unsigned char *seed, size_t seed_len,
                              unsigned char *s_bytes, size_t s_len,
                              unsigned char *t_bytes, size_t t_len);

/**
 * Derive signing randomness from seed and message.
 *
 * Deterministic randomness derivation for signing, providing
 * protection against bad RNG while maintaining security.
 *
 * R = HKDF(seed || sk, message || counter, "KAZ-SIGN-RND")
 *
 * @param seed      Random seed from RNG
 * @param seed_len  Length of seed
 * @param sk        Secret key
 * @param sk_len    Length of secret key
 * @param msg       Message being signed
 * @param msg_len   Length of message
 * @param counter   Attempt counter (for rejection sampling)
 * @param output    Output: derived randomness
 * @param out_len   Desired length of output
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_kdf_derive_signing_randomness(const unsigned char *seed, size_t seed_len,
                                      const unsigned char *sk, size_t sk_len,
                                      const unsigned char *msg, size_t msg_len,
                                      uint32_t counter,
                                      unsigned char *output, size_t out_len);

/**
 * Expand a short seed into arbitrary-length output.
 *
 * Uses HKDF-Expand with the given label for domain separation.
 *
 * @param seed      Input seed
 * @param seed_len  Length of seed
 * @param label     Domain separation label
 * @param label_len Length of label
 * @param output    Output buffer
 * @param out_len   Desired output length
 * @return          KAZ_KDF_SUCCESS on success, error code otherwise
 */
int kaz_kdf_expand_seed(const unsigned char *seed, size_t seed_len,
                        const char *label, size_t label_len,
                        unsigned char *output, size_t out_len);

#ifdef __cplusplus
}
#endif

#endif /* KAZ_KDF_H */
