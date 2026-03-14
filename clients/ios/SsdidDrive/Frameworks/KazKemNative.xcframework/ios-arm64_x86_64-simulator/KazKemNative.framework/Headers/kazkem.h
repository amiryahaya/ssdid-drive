/*
 * KAZ-KEM C Bindings for Swift
 * Post-Quantum Key Encapsulation Mechanism
 */

#ifndef KAZKEM_H
#define KAZKEM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define KAZ_KEM_SUCCESS              0
#define KAZ_KEM_ERROR_INVALID_PARAM -1
#define KAZ_KEM_ERROR_MEMORY        -2
#define KAZ_KEM_ERROR_RNG           -3
#define KAZ_KEM_ERROR_OPENSSL       -4
#define KAZ_KEM_ERROR_MSG_TOO_LARGE -5
#define KAZ_KEM_ERROR_NOT_INIT      -6
#define KAZ_KEM_ERROR_INVALID_LEVEL -7

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

/**
 * Initialize KAZ-KEM with a specific security level.
 *
 * @param level Security level: 128, 192, or 256
 * @return 0 on success, negative error code on failure
 */
int kaz_kem_init(int level);

/**
 * Check if KAZ-KEM is initialized.
 *
 * @return 1 if initialized, 0 otherwise
 */
int kaz_kem_is_initialized(void);

/**
 * Get current security level.
 *
 * @return Security level (128, 192, 256) or 0 if not initialized
 */
int kaz_kem_get_level(void);

/**
 * Cleanup KAZ-KEM state.
 */
void kaz_kem_cleanup(void);

/**
 * Full cleanup including OpenSSL internal state.
 * Call only at final program exit.
 */
void kaz_kem_cleanup_full(void);

/* ============================================================================
 * Size Functions
 * ============================================================================ */

/**
 * Get public key size in bytes for current security level.
 */
size_t kaz_kem_publickey_bytes(void);

/**
 * Get private key size in bytes for current security level.
 */
size_t kaz_kem_privatekey_bytes(void);

/**
 * Get ciphertext size in bytes for current security level.
 */
size_t kaz_kem_ciphertext_bytes(void);

/**
 * Get shared secret size in bytes for current security level.
 */
size_t kaz_kem_shared_secret_bytes(void);

/* ============================================================================
 * Key Generation
 * ============================================================================ */

/**
 * Generate a new key pair.
 *
 * @param pk Output buffer for public key (must be kaz_kem_publickey_bytes() bytes)
 * @param sk Output buffer for private key (must be kaz_kem_privatekey_bytes() bytes)
 * @return 0 on success, negative error code on failure
 */
int kaz_kem_keypair(unsigned char *pk, unsigned char *sk);

/* ============================================================================
 * Encapsulation and Decapsulation
 * ============================================================================ */

/**
 * Encapsulate a shared secret using a public key.
 *
 * @param ct Output buffer for ciphertext
 * @param ctlen Output: actual ciphertext length
 * @param ss Input shared secret to encapsulate
 * @param sslen Length of shared secret
 * @param pk Public key
 * @return 0 on success, negative error code on failure
 */
int kaz_kem_encapsulate(unsigned char *ct, unsigned long long *ctlen,
                        const unsigned char *ss, unsigned long long sslen,
                        const unsigned char *pk);

/**
 * Decapsulate a shared secret using a private key.
 *
 * @param ss Output buffer for shared secret
 * @param sslen Output: actual shared secret length
 * @param ct Ciphertext
 * @param ctlen Ciphertext length
 * @param sk Private key
 * @return 0 on success, negative error code on failure
 */
int kaz_kem_decapsulate(unsigned char *ss, unsigned long long *sslen,
                        const unsigned char *ct, unsigned long long ctlen,
                        const unsigned char *sk);

/* ============================================================================
 * Version Information
 * ============================================================================ */

/**
 * Get version string.
 *
 * @return Pointer to version string (e.g., "2.0.0")
 */
const char* kaz_kem_version(void);

#ifdef __cplusplus
}
#endif

#endif /* KAZKEM_H */
