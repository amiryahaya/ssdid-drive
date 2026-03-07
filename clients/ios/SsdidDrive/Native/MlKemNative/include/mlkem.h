/*
 * ML-KEM Native C Bindings for Swift
 * NIST FIPS 203 ML-KEM-768 Key Encapsulation Mechanism
 *
 * Uses liboqs for the underlying cryptographic implementation.
 */

#ifndef MLKEM_H
#define MLKEM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define ML_KEM_SUCCESS              0
#define ML_KEM_ERROR_INVALID_PARAM -1
#define ML_KEM_ERROR_MEMORY        -2
#define ML_KEM_ERROR_RNG           -3
#define ML_KEM_ERROR_CRYPTO        -4
#define ML_KEM_ERROR_NOT_INIT      -5
#define ML_KEM_ERROR_INVALID_SIZE  -6
#define ML_KEM_ERROR_LIBOQS        -7

/* ============================================================================
 * ML-KEM-768 Parameters (NIST Level 3)
 * ============================================================================ */

#define ML_KEM_768_PUBLIC_KEY_BYTES    1184
#define ML_KEM_768_SECRET_KEY_BYTES    2400
#define ML_KEM_768_CIPHERTEXT_BYTES    1088
#define ML_KEM_768_SHARED_SECRET_BYTES 32

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

/**
 * Initialize ML-KEM library.
 *
 * @return 0 on success, negative error code on failure
 */
int ml_kem_init(void);

/**
 * Check if ML-KEM is initialized.
 *
 * @return 1 if initialized, 0 otherwise
 */
int ml_kem_is_initialized(void);

/**
 * Cleanup ML-KEM state.
 */
void ml_kem_cleanup(void);

/* ============================================================================
 * Size Functions
 * ============================================================================ */

/**
 * Get public key size in bytes.
 */
size_t ml_kem_publickey_bytes(void);

/**
 * Get secret key size in bytes.
 */
size_t ml_kem_secretkey_bytes(void);

/**
 * Get ciphertext size in bytes.
 */
size_t ml_kem_ciphertext_bytes(void);

/**
 * Get shared secret size in bytes.
 */
size_t ml_kem_shared_secret_bytes(void);

/* ============================================================================
 * Key Generation
 * ============================================================================ */

/**
 * Generate a new ML-KEM-768 key pair.
 *
 * @param pk Output buffer for public key (must be ML_KEM_768_PUBLIC_KEY_BYTES bytes)
 * @param sk Output buffer for secret key (must be ML_KEM_768_SECRET_KEY_BYTES bytes)
 * @return 0 on success, negative error code on failure
 */
int ml_kem_keypair(unsigned char *pk, unsigned char *sk);

/* ============================================================================
 * Encapsulation and Decapsulation
 * ============================================================================ */

/**
 * Encapsulate: generate a shared secret and ciphertext using a public key.
 *
 * @param ct Output buffer for ciphertext (must be ML_KEM_768_CIPHERTEXT_BYTES bytes)
 * @param ss Output buffer for shared secret (must be ML_KEM_768_SHARED_SECRET_BYTES bytes)
 * @param pk Public key (must be ML_KEM_768_PUBLIC_KEY_BYTES bytes)
 * @return 0 on success, negative error code on failure
 */
int ml_kem_encapsulate(unsigned char *ct, unsigned char *ss,
                       const unsigned char *pk);

/**
 * Decapsulate: recover the shared secret from a ciphertext using a secret key.
 *
 * @param ss Output buffer for shared secret (must be ML_KEM_768_SHARED_SECRET_BYTES bytes)
 * @param ct Ciphertext (must be ML_KEM_768_CIPHERTEXT_BYTES bytes)
 * @param sk Secret key (must be ML_KEM_768_SECRET_KEY_BYTES bytes)
 * @return 0 on success, negative error code on failure
 */
int ml_kem_decapsulate(unsigned char *ss,
                       const unsigned char *ct,
                       const unsigned char *sk);

/* ============================================================================
 * Version Information
 * ============================================================================ */

/**
 * Get version string.
 *
 * @return Pointer to version string (e.g., "1.0.0")
 */
const char* ml_kem_version(void);

/**
 * Get algorithm name.
 *
 * @return Algorithm name string
 */
const char* ml_kem_algorithm(void);

#ifdef __cplusplus
}
#endif

#endif /* MLKEM_H */
