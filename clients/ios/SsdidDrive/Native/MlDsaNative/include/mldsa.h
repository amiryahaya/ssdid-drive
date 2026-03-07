/*
 * ML-DSA Native C Bindings for Swift
 * NIST FIPS 204 ML-DSA-65 Digital Signature Algorithm
 *
 * Uses liboqs for the underlying cryptographic implementation.
 */

#ifndef MLDSA_H
#define MLDSA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define ML_DSA_SUCCESS              0
#define ML_DSA_ERROR_INVALID_PARAM -1
#define ML_DSA_ERROR_MEMORY        -2
#define ML_DSA_ERROR_RNG           -3
#define ML_DSA_ERROR_CRYPTO        -4
#define ML_DSA_ERROR_NOT_INIT      -5
#define ML_DSA_ERROR_INVALID_SIZE  -6
#define ML_DSA_ERROR_LIBOQS        -7
#define ML_DSA_ERROR_VERIFY_FAILED -8

/* ============================================================================
 * ML-DSA-65 Parameters (NIST Level 3)
 * ============================================================================ */

#define ML_DSA_65_PUBLIC_KEY_BYTES  1952
#define ML_DSA_65_SECRET_KEY_BYTES  4032
#define ML_DSA_65_SIGNATURE_BYTES   3309

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

/**
 * Initialize ML-DSA library.
 *
 * @return 0 on success, negative error code on failure
 */
int ml_dsa_init(void);

/**
 * Check if ML-DSA is initialized.
 *
 * @return 1 if initialized, 0 otherwise
 */
int ml_dsa_is_initialized(void);

/**
 * Cleanup ML-DSA state.
 */
void ml_dsa_cleanup(void);

/* ============================================================================
 * Size Functions
 * ============================================================================ */

/**
 * Get public key size in bytes.
 */
size_t ml_dsa_publickey_bytes(void);

/**
 * Get secret key size in bytes.
 */
size_t ml_dsa_secretkey_bytes(void);

/**
 * Get maximum signature size in bytes.
 */
size_t ml_dsa_signature_bytes(void);

/* ============================================================================
 * Key Generation
 * ============================================================================ */

/**
 * Generate a new ML-DSA-65 key pair.
 *
 * @param pk Output buffer for public key (must be ML_DSA_65_PUBLIC_KEY_BYTES bytes)
 * @param sk Output buffer for secret key (must be ML_DSA_65_SECRET_KEY_BYTES bytes)
 * @return 0 on success, negative error code on failure
 */
int ml_dsa_keypair(unsigned char *pk, unsigned char *sk);

/* ============================================================================
 * Signing and Verification
 * ============================================================================ */

/**
 * Sign a message.
 *
 * @param sig Output buffer for signature (must be at least ML_DSA_65_SIGNATURE_BYTES bytes)
 * @param siglen Output: actual signature length
 * @param msg Message to sign
 * @param msglen Length of message
 * @param sk Secret key (must be ML_DSA_65_SECRET_KEY_BYTES bytes)
 * @return 0 on success, negative error code on failure
 */
int ml_dsa_sign(unsigned char *sig, size_t *siglen,
                const unsigned char *msg, size_t msglen,
                const unsigned char *sk);

/**
 * Verify a signature.
 *
 * @param msg Message that was signed
 * @param msglen Length of message
 * @param sig Signature to verify
 * @param siglen Length of signature
 * @param pk Public key (must be ML_DSA_65_PUBLIC_KEY_BYTES bytes)
 * @return 0 on valid signature, ML_DSA_ERROR_VERIFY_FAILED on invalid, negative on error
 */
int ml_dsa_verify(const unsigned char *msg, size_t msglen,
                  const unsigned char *sig, size_t siglen,
                  const unsigned char *pk);

/* ============================================================================
 * Version Information
 * ============================================================================ */

/**
 * Get version string.
 *
 * @return Pointer to version string (e.g., "1.0.0")
 */
const char* ml_dsa_version(void);

/**
 * Get algorithm name.
 *
 * @return Algorithm name string
 */
const char* ml_dsa_algorithm(void);

#ifdef __cplusplus
}
#endif

#endif /* MLDSA_H */
