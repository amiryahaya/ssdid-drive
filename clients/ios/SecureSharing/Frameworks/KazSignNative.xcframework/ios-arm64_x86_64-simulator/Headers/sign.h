/*
 * KAZ-SIGN: Post-Quantum Digital Signature Algorithm
 * Version 2.1
 *
 * Unified implementation supporting security levels 128, 192, and 256
 * Uses OpenSSL BIGNUM with constant-time operations
 *
 * Supports both compile-time and runtime security level selection.
 *
 * NIST-developed software is provided by NIST as a public service.
 */

#ifndef KAZ_SIGN_H
#define KAZ_SIGN_H

#include <stddef.h>
#include <stdint.h>

/* ============================================================================
 * Version Information
 * ============================================================================ */

#define KAZ_SIGN_VERSION_MAJOR     2
#define KAZ_SIGN_VERSION_MINOR     1
#define KAZ_SIGN_VERSION_PATCH     0
#define KAZ_SIGN_VERSION_STRING    "2.1.0"

/* Version as single integer: (major * 10000) + (minor * 100) + patch */
#define KAZ_SIGN_VERSION_NUMBER    20100

/* ============================================================================
 * Runtime Security Level Selection (NEW in 2.1)
 * ============================================================================ */

/**
 * Security level enumeration for runtime selection
 */
typedef enum {
    KAZ_LEVEL_128 = 128,    /* 128-bit security (SHA-256) */
    KAZ_LEVEL_192 = 192,    /* 192-bit security (SHA-384) */
    KAZ_LEVEL_256 = 256     /* 256-bit security (SHA-512) */
} kaz_sign_level_t;

/**
 * Security level parameters (read-only, for introspection)
 */
typedef struct {
    int level;                  /* Security level (128, 192, 256) */
    const char *algorithm_name; /* Algorithm name string */
    size_t secret_key_bytes;    /* Secret key size */
    size_t public_key_bytes;    /* Public key size */
    size_t hash_bytes;          /* Hash output size */
    size_t signature_overhead;  /* Signature size without message */
    size_t s_bytes;             /* s component size */
    size_t t_bytes;             /* t component size */
    size_t s1_bytes;            /* S1 component size */
    size_t s2_bytes;            /* S2 component size */
    size_t s3_bytes;            /* S3 component size */
} kaz_sign_level_params_t;

/**
 * Get parameters for a security level
 *
 * @param level  Security level (KAZ_LEVEL_128, KAZ_LEVEL_192, or KAZ_LEVEL_256)
 * @return Pointer to level parameters, or NULL if invalid level
 */
const kaz_sign_level_params_t *kaz_sign_get_level_params(kaz_sign_level_t level);

/* ============================================================================
 * Compile-time Security Level Selection (Legacy, for backwards compatibility)
 * Set KAZ_SECURITY_LEVEL to 128, 192, or 256
 * ============================================================================ */

#ifndef KAZ_SECURITY_LEVEL
#define KAZ_SECURITY_LEVEL 128
#endif

/* Validate security level */
#if KAZ_SECURITY_LEVEL != 128 && KAZ_SECURITY_LEVEL != 192 && KAZ_SECURITY_LEVEL != 256
#error "KAZ_SECURITY_LEVEL must be 128, 192, or 256"
#endif

/* ============================================================================
 * Security Level 128 Parameters
 * ============================================================================ */
#if KAZ_SECURITY_LEVEL == 128

#define KAZ_SIGN_ALGNAME           "KAZ-SIGN-128"
#define KAZ_SIGN_SECRETKEYBYTES    32
#define KAZ_SIGN_PUBLICKEYBYTES    54
#define KAZ_SIGN_BYTES             32

#define KAZ_SIGN_SP_J              128
#define KAZ_SIGN_SP_g1             "65537"
#define KAZ_SIGN_SP_g2             "65539"

#define KAZ_SIGN_SP_N              "9680693320350411581735712527156160041331448806285781880953481207107506184928318589548473667621840334803765737814574120142199988285"
#define KAZ_SIGN_SP_phiN           "1862854061641389163337017925599133865006616816206541406153748908271169581801631840410608441366518309266967756800000000000000000000"

#define KAZ_SIGN_SP_Og1N           "104096837085595768062256170741230052000"
#define KAZ_SIGN_SP_Og2N           "17349472847599294677042695123538342000"

#define KAZ_SIGN_VBYTES            54
#define KAZ_SIGN_SBYTES            16
#define KAZ_SIGN_TBYTES            16
#define KAZ_SIGN_S1BYTES           54
#define KAZ_SIGN_S2BYTES           54
#define KAZ_SIGN_S3BYTES           54

/* Hash function: SHA-256 */
#define KAZ_SIGN_HASH_ALG          "SHA256"

/* ============================================================================
 * Security Level 192 Parameters
 * ============================================================================ */
#elif KAZ_SECURITY_LEVEL == 192

#define KAZ_SIGN_ALGNAME           "KAZ-SIGN-192"
#define KAZ_SIGN_SECRETKEYBYTES    50
#define KAZ_SIGN_PUBLICKEYBYTES    88
#define KAZ_SIGN_BYTES             48

#define KAZ_SIGN_SP_J              192
#define KAZ_SIGN_SP_g1             "65537"
#define KAZ_SIGN_SP_g2             "65539"

#define KAZ_SIGN_SP_N              "15982040643598444277320371265136974856402799594720686504760818091215333991414038871394426514903965899103553442859146701270930684879295849706045338879593833465052745734862675359470536861467492521046077102660572015"
#define KAZ_SIGN_SP_phiN           "2852982385092065996343896318300390927321234264319221230294884622249277900787903710363361658485275185133309433619496986167576406960701801204725152385400156421631204526170043735085154304000000000000000000000000000"

#define KAZ_SIGN_SP_Og1N           "12934000239870021828648909535012878456790556542848408504000"
#define KAZ_SIGN_SP_Og2N           "12934000239870021828648909535012878456790556542848408504000"

#define KAZ_SIGN_VBYTES            88
#define KAZ_SIGN_SBYTES            25
#define KAZ_SIGN_TBYTES            25
#define KAZ_SIGN_S1BYTES           88
#define KAZ_SIGN_S2BYTES           88
#define KAZ_SIGN_S3BYTES           88

/* Hash function: SHA-384 */
#define KAZ_SIGN_HASH_ALG          "SHA384"

/* ============================================================================
 * Security Level 256 Parameters
 * ============================================================================ */
#elif KAZ_SECURITY_LEVEL == 256

#define KAZ_SIGN_ALGNAME           "KAZ-SIGN-256"
#define KAZ_SIGN_SECRETKEYBYTES    64
#define KAZ_SIGN_PUBLICKEYBYTES    118
#define KAZ_SIGN_BYTES             64

#define KAZ_SIGN_SP_J              256
#define KAZ_SIGN_SP_g1             "65537"
#define KAZ_SIGN_SP_g2             "65539"

#define KAZ_SIGN_SP_N              "29421818394147345935036136135391375994024126405325576672227398037493559452008116283594709069097880319117946343281357631447556041903884586208161678710597469727999746179863045388559147407457068275815914914983896392757878683919189075898269550939868181179868469970964809582599153788719655"
#define KAZ_SIGN_SP_phiN           "502924248251635525629785876194372240141863912168458452749995697467455160087932504342175710330632944142887080586716346345907214888007643703094458414828200990128223075181127530152432620200757034038485458163071614226834741804596849230360138563704586240000000000000000000000000000000000000"

#define KAZ_SIGN_SP_Og1N           "49577346943749914278558040936897577826073730777121114343013903022328490384000"
#define KAZ_SIGN_SP_Og2N           "24788673471874957139279020468448788913036865388560557171506951511164245192000"

#define KAZ_SIGN_VBYTES            118
#define KAZ_SIGN_SBYTES            32
#define KAZ_SIGN_TBYTES            32
/* Note: S2, S3 are mod phi(N) which has 285 digits = 119 bytes */
#define KAZ_SIGN_S1BYTES           118
#define KAZ_SIGN_S2BYTES           119
#define KAZ_SIGN_S3BYTES           119

/* Hash function: SHA-512 */
#define KAZ_SIGN_HASH_ALG          "SHA512"

#endif /* KAZ_SECURITY_LEVEL */

/* ============================================================================
 * Derived Constants
 * ============================================================================ */

/* Total signature overhead (without message) */
#define KAZ_SIGN_SIGNATURE_OVERHEAD (KAZ_SIGN_S1BYTES + KAZ_SIGN_S2BYTES + KAZ_SIGN_S3BYTES)

/* Backend information */
#define KAZ_SIGN_BACKEND "OpenSSL (constant-time)"

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define KAZ_SIGN_SUCCESS           0
#define KAZ_SIGN_ERROR_MEMORY     -1
#define KAZ_SIGN_ERROR_RNG        -2
#define KAZ_SIGN_ERROR_INVALID    -3
#define KAZ_SIGN_ERROR_VERIFY     -4

/* ============================================================================
 * Random State Management
 * ============================================================================ */

/**
 * Initialize the global random state with proper entropy
 * MUST be called before any signing operations
 *
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_init_random(void);

/**
 * Clear and free the global random state
 * Should be called when done with signing operations
 */
void kaz_sign_clear_random(void);

/**
 * Check if random state has been initialized
 *
 * @return 1 if initialized, 0 otherwise
 */
int kaz_sign_is_initialized(void);

/* ============================================================================
 * Core KAZ-SIGN API
 * ============================================================================ */

/**
 * Generate a KAZ-SIGN key pair
 *
 * @param pk  Output: public verification key (KAZ_SIGN_PUBLICKEYBYTES bytes)
 * @param sk  Output: secret signing key (KAZ_SIGN_SECRETKEYBYTES bytes)
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_keypair(unsigned char *pk, unsigned char *sk);

/**
 * Sign a message
 *
 * @param sig      Output: signature (KAZ_SIGN_SIGNATURE_OVERHEAD + mlen bytes)
 * @param siglen   Output: length of signature
 * @param msg      Input: message to sign
 * @param msglen   Input: length of message
 * @param sk       Input: secret signing key
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_signature(unsigned char *sig,
                       unsigned long long *siglen,
                       const unsigned char *msg,
                       unsigned long long msglen,
                       const unsigned char *sk);

/**
 * Verify a signature and extract the message
 *
 * @param msg      Output: extracted message
 * @param msglen   Output: length of extracted message
 * @param sig      Input: signature (signature || message)
 * @param siglen   Input: length of signature
 * @param pk       Input: public verification key
 * @return KAZ_SIGN_SUCCESS if valid, KAZ_SIGN_ERROR_VERIFY if invalid
 */
int kaz_sign_verify(unsigned char *msg,
                    unsigned long long *msglen,
                    const unsigned char *sig,
                    unsigned long long siglen,
                    const unsigned char *pk);

/**
 * Hash a message using the appropriate hash function for the security level
 *
 * @param msg     Input: message to hash
 * @param msglen  Input: length of message
 * @param hash    Output: hash value (KAZ_SIGN_BYTES bytes)
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_hash(const unsigned char *msg,
                  unsigned long long msglen,
                  unsigned char *hash);

/* ============================================================================
 * Version API
 * ============================================================================ */

/**
 * Get the version string
 *
 * @return Version string (e.g., "2.0.0")
 */
const char *kaz_sign_version(void);

/**
 * Get the version number as integer
 *
 * @return Version number (major * 10000 + minor * 100 + patch)
 */
int kaz_sign_version_number(void);

/* ============================================================================
 * Runtime Security Level API (NEW in 2.1)
 *
 * These functions allow selecting the security level at runtime.
 * Use these for applications that need to support multiple security levels.
 * ============================================================================ */

/**
 * Initialize the library for a specific security level
 * Can be called multiple times with different levels.
 *
 * @param level  Security level (KAZ_LEVEL_128, KAZ_LEVEL_192, or KAZ_LEVEL_256)
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_init_level(kaz_sign_level_t level);

/**
 * Clear resources for a specific security level
 *
 * @param level  Security level to clear
 */
void kaz_sign_clear_level(kaz_sign_level_t level);

/**
 * Clear resources for all security levels
 */
void kaz_sign_clear_all(void);

/**
 * Generate a key pair for a specific security level
 *
 * @param level  Security level
 * @param pk     Output: public key (size from kaz_sign_get_level_params)
 * @param sk     Output: secret key (size from kaz_sign_get_level_params)
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_keypair_ex(kaz_sign_level_t level,
                        unsigned char *pk,
                        unsigned char *sk);

/**
 * Sign a message with a specific security level
 *
 * @param level   Security level
 * @param sig     Output: signature (overhead + msglen bytes)
 * @param siglen  Output: length of signature
 * @param msg     Input: message to sign
 * @param msglen  Input: length of message
 * @param sk      Input: secret key
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_signature_ex(kaz_sign_level_t level,
                          unsigned char *sig,
                          unsigned long long *siglen,
                          const unsigned char *msg,
                          unsigned long long msglen,
                          const unsigned char *sk);

/**
 * Verify a signature with a specific security level
 *
 * @param level   Security level
 * @param msg     Output: extracted message
 * @param msglen  Output: length of extracted message
 * @param sig     Input: signature
 * @param siglen  Input: length of signature
 * @param pk      Input: public key
 * @return KAZ_SIGN_SUCCESS if valid, KAZ_SIGN_ERROR_VERIFY if invalid
 */
int kaz_sign_verify_ex(kaz_sign_level_t level,
                       unsigned char *msg,
                       unsigned long long *msglen,
                       const unsigned char *sig,
                       unsigned long long siglen,
                       const unsigned char *pk);

/**
 * Hash a message with the hash function for a specific security level
 *
 * @param level   Security level
 * @param msg     Input: message to hash
 * @param msglen  Input: length of message
 * @param hash    Output: hash value (size from kaz_sign_get_level_params)
 * @return KAZ_SIGN_SUCCESS on success, error code otherwise
 */
int kaz_sign_hash_ex(kaz_sign_level_t level,
                     const unsigned char *msg,
                     unsigned long long msglen,
                     unsigned char *hash);

#endif /* KAZ_SIGN_H */
