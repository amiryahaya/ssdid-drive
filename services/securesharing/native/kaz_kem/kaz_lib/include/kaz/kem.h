/*
 * KAZ-KEM API Header
 * Version 2.1.0
 *
 * Post-quantum Key Encapsulation Mechanism
 * Supports Security Levels: 128, 192, 256 (runtime selectable)
 *
 * Implementation: OpenSSL BIGNUM with constant-time operations
 * - BN_mod_exp_mont_consttime() for timing attack resistance
 * - OpenSSL RAND for cryptographic random number generation
 * - Secure memory handling with BN_clear_free()
 */

#ifndef KAZ_KEM_API_H_INCLUDED
#define KAZ_KEM_API_H_INCLUDED

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * SECURITY LEVELS
 * ============================================================================ */

#define KAZ_KEM_LEVEL_128   128
#define KAZ_KEM_LEVEL_192   192
#define KAZ_KEM_LEVEL_256   256

/* ============================================================================
 * PARAMETER STRUCTURE
 * ============================================================================ */

/**
 * Security level parameters structure.
 * Contains all parameters for a specific security level.
 */
typedef struct {
    int security_level;         /* 128, 192, or 256 */
    int J;                      /* Parameter J */

    const char *N;              /* Modulus N as decimal string */
    int LN;                     /* Bit length of N */

    const char *g1;             /* Generator 1 */
    const char *g2;             /* Generator 2 */
    const char *g3;             /* Generator 3 */

    const char *Og1N;           /* Order of g1 mod N */
    int LOg1N;                  /* Bit length of Og1N */
    const char *Og2N;           /* Order of g2 mod N */
    int LOg2N;                  /* Bit length of Og2N */
    const char *Og3N;           /* Order of g3 mod N */
    int LOg3N;                  /* Bit length of Og3N */

    size_t publickey_bytes;     /* Size of each public key component (A1, A2) */
    size_t privatekey_bytes;    /* Size of each private key component (a1, a2) */
    size_t ephemeral_public_bytes;  /* Size of ephemeral public key (B1, B2) */
    size_t ephemeral_private_bytes; /* Size of ephemeral private key (b1, b2) */
    size_t general_bytes;       /* Size of message/general data */
} kaz_kem_params_t;

/* ============================================================================
 * INITIALIZATION AND PARAMETER ACCESS
 * ============================================================================ */

/**
 * Initialize KAZ-KEM with a specific security level.
 * Must be called before any other KEM operations.
 *
 * @param level  Security level (128, 192, or 256)
 * @return       0 on success, negative error code on failure
 */
extern int kaz_kem_init(int level);

/**
 * Get the current security level.
 *
 * @return  Current security level (128, 192, or 256), or 0 if not initialized
 */
extern int kaz_kem_get_level(void);

/**
 * Get the current parameters structure.
 *
 * @return  Pointer to current parameters, or NULL if not initialized
 */
extern const kaz_kem_params_t* kaz_kem_get_params(void);

/**
 * Check if KAZ-KEM is initialized.
 *
 * @return  1 if initialized, 0 otherwise
 */
extern int kaz_kem_is_initialized(void);

/* ============================================================================
 * SIZE ACCESSOR FUNCTIONS
 * ============================================================================ */

/**
 * Get public key size in bytes.
 * Returns total size (2 components).
 */
extern size_t kaz_kem_publickey_bytes(void);

/**
 * Get private key size in bytes.
 * Returns total size (2 components).
 */
extern size_t kaz_kem_privatekey_bytes(void);

/**
 * Get encapsulation (ciphertext) size in bytes.
 */
extern size_t kaz_kem_ciphertext_bytes(void);

/**
 * Get shared secret (message) size in bytes.
 */
extern size_t kaz_kem_shared_secret_bytes(void);

/* ============================================================================
 * CORE KEM FUNCTIONS
 * ============================================================================ */

/**
 * Generate a KEM key pair.
 *
 * @param pk    Output buffer for public key (kaz_kem_publickey_bytes())
 * @param sk    Output buffer for private key (kaz_kem_privatekey_bytes())
 * @return      0 on success, negative error code on failure
 */
extern int kaz_kem_keypair(unsigned char *pk, unsigned char *sk);

/**
 * Encapsulate a message/shared secret.
 *
 * @param ct        Output buffer for ciphertext (kaz_kem_ciphertext_bytes())
 * @param ctlen     Output: length of ciphertext
 * @param ss        Input shared secret (must be < modulus N)
 * @param sslen     Length of shared secret
 * @param pk        Public key from kaz_kem_keypair
 * @return          0 on success, negative error code on failure
 */
extern int kaz_kem_encapsulate(unsigned char *ct, unsigned long long *ctlen,
                               const unsigned char *ss, unsigned long long sslen,
                               const unsigned char *pk);

/**
 * Decapsulate to recover the original shared secret.
 *
 * @param ss        Output buffer for shared secret
 * @param sslen     Output: length of shared secret
 * @param ct        Ciphertext from kaz_kem_encapsulate
 * @param ctlen     Length of ciphertext
 * @param sk        Private key from kaz_kem_keypair
 * @return          0 on success, negative error code on failure
 */
extern int kaz_kem_decapsulate(unsigned char *ss, unsigned long long *sslen,
                               const unsigned char *ct, unsigned long long ctlen,
                               const unsigned char *sk);

/**
 * Cleanup KEM state and securely clear sensitive data.
 * Should be called at program exit or before reinitializing with a new level.
 */
extern void kaz_kem_cleanup(void);

/**
 * Full cleanup including OpenSSL internal state.
 * Call only at final program exit - OpenSSL cannot be used after this.
 * This eliminates all memory leaks from OpenSSL's internal caches.
 */
extern void kaz_kem_cleanup_full(void);

/**
 * Get version string at runtime.
 * Returns: Pointer to version string (e.g., "2.1.0")
 * Note: The returned string is statically allocated and should not be freed.
 */
extern const char* kaz_kem_version(void);

/* ============================================================================
 * ERROR CODES
 * ============================================================================ */

#define KAZ_KEM_SUCCESS              0
#define KAZ_KEM_ERROR_INVALID_PARAM -1
#define KAZ_KEM_ERROR_RNG           -2
#define KAZ_KEM_ERROR_MEMORY        -3
#define KAZ_KEM_ERROR_OPENSSL       -4
#define KAZ_KEM_ERROR_MSG_TOO_LARGE -5
#define KAZ_KEM_ERROR_NOT_INIT      -6
#define KAZ_KEM_ERROR_INVALID_LEVEL -7

#ifdef __cplusplus
}
#endif

#endif /* KAZ_KEM_API_H_INCLUDED */
