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
 * BACKWARD COMPATIBILITY API
 * These functions maintain compatibility with the compile-time API.
 * They call the new runtime API internally.
 * ============================================================================ */

#ifdef KAZ_SECURITY_LEVEL
/* Compile-time macros for backward compatibility */

#if KAZ_SECURITY_LEVEL == 128
#define KAZ_KEM_SP_J                        65
#define KAZ_KEM_SP_SL                       128
#define KAZ_KEM_SP_N                        "9680693320350411581735712527156160041331448806285781880953481207107506184928318589548473667621840334803765737814574120142199988285"
#define KAZ_KEM_SP_LN                       432
#define KAZ_KEM_SP_g1                       "7"
#define KAZ_KEM_SP_g2                       "23"
#define KAZ_KEM_SP_g3                       "65537"
#define KAZ_KEM_SP_Og1N                     "832774696684766144498049365929840416000"
#define KAZ_KEM_SP_LOg1N                    130
#define KAZ_KEM_SP_Og2N                     "23132630463465726236056926831384456000"
#define KAZ_KEM_SP_LOg2N                    125
#define KAZ_KEM_SP_Og3N                     "104096837085595768062256170741230052000"
#define KAZ_KEM_SP_LOg3N                    127
#define KAZ_KEM_PUBLICKEY_BYTES             54
#define KAZ_KEM_PRIVATEKEY_BYTES            17
#define KAZ_KEM_EPHERMERAL_PUBLIC_BYTES     54
#define KAZ_KEM_EPHERMERAL_PRIVATE_BYTES    17
#define KAZ_KEM_GENERAL_BYTES               54

#elif KAZ_SECURITY_LEVEL == 192
#define KAZ_KEM_SP_J                        96
#define KAZ_KEM_SP_SL                       192
#define KAZ_KEM_SP_N                        "15982040643598444277320371265136974856402799594720686504760818091215333991414038871394426514903965899103553442859146701270930684879295849706045338879593833465052745734862675359470536861467492521046077102660572015"
#define KAZ_KEM_SP_LN                       702
#define KAZ_KEM_SP_g1                       "7"
#define KAZ_KEM_SP_g2                       "23"
#define KAZ_KEM_SP_g3                       "65537"
#define KAZ_KEM_SP_Og1N                     "51736000959480087314595638140051513827162226171393634016000"
#define KAZ_KEM_SP_LOg1N                    196
#define KAZ_KEM_SP_Og2N                     "38802000719610065485946728605038635370371669628545225512000"
#define KAZ_KEM_SP_LOg2N                    195
#define KAZ_KEM_SP_Og3N                     "12934000239870021828648909535012878456790556542848408504000"
#define KAZ_KEM_SP_LOg3N                    194
#define KAZ_KEM_PUBLICKEY_BYTES             88
#define KAZ_KEM_PRIVATEKEY_BYTES            25
#define KAZ_KEM_EPHERMERAL_PUBLIC_BYTES     88
#define KAZ_KEM_EPHERMERAL_PRIVATE_BYTES    25
#define KAZ_KEM_GENERAL_BYTES               88

#elif KAZ_SECURITY_LEVEL == 256
#define KAZ_KEM_SP_J                        122
#define KAZ_KEM_SP_SL                       256
#define KAZ_KEM_SP_N                        "29421818394147345935036136135391375994024126405325576672227398037493559452008116283594709069097880319117946343281357631447556041903884586208161678710597469727999746179863045388559147407457068275815914914983896392757878683919189075898269550939868181179868469970964809582599153788719655"
#define KAZ_KEM_SP_LN                       942
#define KAZ_KEM_SP_g1                       "7"
#define KAZ_KEM_SP_g2                       "23"
#define KAZ_KEM_SP_g3                       "65537"
#define KAZ_KEM_SP_Og1N                     "99154693887499828557116081873795155652147461554242228686027806044656980768000"
#define KAZ_KEM_SP_LOg1N                    256
#define KAZ_KEM_SP_Og2N                     "148732040831249742835674122810692733478221192331363343029041709066985471152000"
#define KAZ_KEM_SP_LOg2N                    257
#define KAZ_KEM_SP_Og3N                     "49577346943749914278558040936897577826073730777121114343013903022328490384000"
#define KAZ_KEM_SP_LOg3N                    255
#define KAZ_KEM_PUBLICKEY_BYTES             118
#define KAZ_KEM_PRIVATEKEY_BYTES            33
#define KAZ_KEM_EPHERMERAL_PUBLIC_BYTES     118
#define KAZ_KEM_EPHERMERAL_PRIVATE_BYTES    33
#define KAZ_KEM_GENERAL_BYTES               118
#endif

/* Legacy function names (call runtime API with auto-init) */
extern int KAZ_KEM_KEYGEN(unsigned char *pk, unsigned char *sk);
extern int KAZ_KEM_ENCAPSULATION(unsigned char *encap, unsigned long long *encaplen,
                                 const unsigned char *m, unsigned long long mlen,
                                 const unsigned char *pk);
extern int KAZ_KEM_DECAPSULATION(unsigned char *decap, unsigned long long *decaplen,
                                 const unsigned char *encap, unsigned long long encaplen,
                                 const unsigned char *sk);
extern void KAZ_KEM_CLEANUP(void);

#endif /* KAZ_SECURITY_LEVEL */

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
