/*
 * KAZ-KEM Secure Implementation
 * Version 2.0.0
 *
 * Production-hardened implementation with runtime security level selection using:
 * - OpenSSL BIGNUM with constant-time operations
 * - OpenSSL RAND_bytes for cryptographic RNG
 * - Secure memory handling
 * - Side-channel resistant operations
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/bn.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <openssl/crypto.h>

#include "kaz/kem.h"
#include "kaz/security.h"

/* ============================================================================
 * STATIC PARAMETER DEFINITIONS FOR ALL SECURITY LEVELS
 * ============================================================================ */

static const kaz_kem_params_t KAZ_KEM_PARAMS_128 = {
    .security_level = 128,
    .J = 65,
    .N = "9680693320350411581735712527156160041331448806285781880953481207107506184928318589548473667621840334803765737814574120142199988285",
    .LN = 432,
    .g1 = "7",
    .g2 = "23",
    .Og1N = "832774696684766144498049365929840416000",
    .LOg1N = 130,
    .Og2N = "23132630463465726236056926831384456000",
    .LOg2N = 125,
    .publickey_bytes = 54,
    .privatekey_bytes = 17,
    .ephemeral_public_bytes = 54,
    .ephemeral_private_bytes = 17,
    .general_bytes = 54
};

static const kaz_kem_params_t KAZ_KEM_PARAMS_192 = {
    .security_level = 192,
    .J = 96,
    .N = "15982040643598444277320371265136974856402799594720686504760818091215333991414038871394426514903965899103553442859146701270930684879295849706045338879593833465052745734862675359470536861467492521046077102660572015",
    .LN = 702,
    .g1 = "7",
    .g2 = "23",
    .Og1N = "51736000959480087314595638140051513827162226171393634016000",
    .LOg1N = 196,
    .Og2N = "38802000719610065485946728605038635370371669628545225512000",
    .LOg2N = 195,
    .publickey_bytes = 88,
    .privatekey_bytes = 25,
    .ephemeral_public_bytes = 88,
    .ephemeral_private_bytes = 25,
    .general_bytes = 88
};

static const kaz_kem_params_t KAZ_KEM_PARAMS_256 = {
    .security_level = 256,
    .J = 122,
    .N = "29421818394147345935036136135391375994024126405325576672227398037493559452008116283594709069097880319117946343281357631447556041903884586208161678710597469727999746179863045388559147407457068275815914914983896392757878683919189075898269550939868181179868469970964809582599153788719655",
    .LN = 942,
    .g1 = "7",
    .g2 = "23",
    .Og1N = "99154693887499828557116081873795155652147461554242228686027806044656980768000",
    .LOg1N = 256,
    .Og2N = "148732040831249742835674122810692733478221192331363343029041709066985471152000",
    .LOg2N = 257,
    .publickey_bytes = 118,
    .privatekey_bytes = 33,
    .ephemeral_public_bytes = 118,
    .ephemeral_private_bytes = 33,
    .general_bytes = 118
};

/* ============================================================================
 * Global State Management
 * ============================================================================ */

typedef struct {
    int initialized;
    const kaz_kem_params_t *params;  /* Pointer to current parameters */
    BN_CTX *bn_ctx;
    BIGNUM *N;      /* Modulus */
    BIGNUM *g1;     /* Generator 1 */
    BIGNUM *g2;     /* Generator 2 */
    BIGNUM *Og1N;   /* Order of g1 mod N */
    BIGNUM *Og2N;   /* Order of g2 mod N */
    BN_MONT_CTX *mont_ctx;  /* Montgomery context for faster modexp */
} kaz_kem_state_t;

static kaz_kem_state_t g_state = {0};

/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void kaz_kem_clear_state(void);

/* ============================================================================
 * Secure Random Number Generation
 * ============================================================================ */

/**
 * Generate a random BIGNUM in range [lb, ub] using OpenSSL RAND_bytes.
 */
static int kaz_kem_secure_random(const BIGNUM *lb, const BIGNUM *ub, BIGNUM *out)
{
    BIGNUM *range = NULL;
    BIGNUM *rand_val = NULL;
    int ret = KAZ_KEM_ERROR_RNG;
    int num_bits;

    range = BN_new();
    rand_val = BN_new();
    if (!range || !rand_val) {
        goto cleanup;
    }

    /* Compute range = ub - lb + 1 */
    if (!BN_sub(range, ub, lb)) goto cleanup;
    if (!BN_add_word(range, 1)) goto cleanup;

    /* Get number of bits needed */
    num_bits = BN_num_bits(range);

    /* Generate random number in [0, range) with rejection sampling */
    do {
        if (!BN_rand(rand_val, num_bits, BN_RAND_TOP_ANY, BN_RAND_BOTTOM_ANY)) {
            goto cleanup;
        }
    } while (BN_cmp(rand_val, range) >= 0);

    /* out = lb + rand_val */
    if (!BN_add(out, lb, rand_val)) goto cleanup;

    ret = KAZ_KEM_SUCCESS;

cleanup:
    BN_clear_free(rand_val);
    BN_clear_free(range);
    return ret;
}

/* ============================================================================
 * Initialization and Cleanup
 * ============================================================================ */

/**
 * Clear all KEM state and zeroize sensitive data.
 */
static void kaz_kem_clear_state(void)
{
    if (g_state.mont_ctx) {
        BN_MONT_CTX_free(g_state.mont_ctx);
        g_state.mont_ctx = NULL;
    }
    BN_clear_free(g_state.N);
    BN_clear_free(g_state.g1);
    BN_clear_free(g_state.g2);
    BN_clear_free(g_state.Og1N);
    BN_clear_free(g_state.Og2N);
    if (g_state.bn_ctx) {
        BN_CTX_free(g_state.bn_ctx);
        g_state.bn_ctx = NULL;
    }
    g_state.N = NULL;
    g_state.g1 = NULL;
    g_state.g2 = NULL;
    g_state.Og1N = NULL;
    g_state.Og2N = NULL;
    g_state.params = NULL;
    g_state.initialized = 0;
}

/**
 * Initialize KAZ-KEM with a specific security level.
 */
int kaz_kem_init(int level)
{
    const kaz_kem_params_t *params;

    /* Select parameters based on level */
    switch (level) {
        case 128:
            params = &KAZ_KEM_PARAMS_128;
            break;
        case 192:
            params = &KAZ_KEM_PARAMS_192;
            break;
        case 256:
            params = &KAZ_KEM_PARAMS_256;
            break;
        default:
            return KAZ_KEM_ERROR_INVALID_LEVEL;
    }

    /* If already initialized with same level, skip */
    if (g_state.initialized && g_state.params == params) {
        return KAZ_KEM_SUCCESS;
    }

    /* Clear any existing state */
    kaz_kem_clear_state();

    /* Store parameters pointer */
    g_state.params = params;

    /* Initialize BN context */
    g_state.bn_ctx = BN_CTX_new();
    if (!g_state.bn_ctx) {
        return KAZ_KEM_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    g_state.N = BN_new();
    g_state.g1 = BN_new();
    g_state.g2 = BN_new();
    g_state.Og1N = BN_new();
    g_state.Og2N = BN_new();

    if (!g_state.N || !g_state.g1 || !g_state.g2 ||
        !g_state.Og1N || !g_state.Og2N) {
        kaz_kem_clear_state();
        return KAZ_KEM_ERROR_MEMORY;
    }

    /* Set system parameters from runtime parameters */
    if (!BN_dec2bn(&g_state.N, params->N)) goto error;
    if (!BN_dec2bn(&g_state.g1, params->g1)) goto error;
    if (!BN_dec2bn(&g_state.g2, params->g2)) goto error;
    if (!BN_dec2bn(&g_state.Og1N, params->Og1N)) goto error;
    if (!BN_dec2bn(&g_state.Og2N, params->Og2N)) goto error;

    /* Set constant-time flag on secret-related values */
    BN_set_flags(g_state.Og1N, BN_FLG_CONSTTIME);
    BN_set_flags(g_state.Og2N, BN_FLG_CONSTTIME);

    /* Initialize Montgomery context for faster modular exponentiation */
    g_state.mont_ctx = BN_MONT_CTX_new();
    if (!g_state.mont_ctx) goto error;
    if (!BN_MONT_CTX_set(g_state.mont_ctx, g_state.N, g_state.bn_ctx)) goto error;

    g_state.initialized = 1;
    return KAZ_KEM_SUCCESS;

error:
    kaz_kem_clear_state();
    return KAZ_KEM_ERROR_OPENSSL;
}

/* ============================================================================
 * Parameter Access Functions
 * ============================================================================ */

int kaz_kem_get_level(void)
{
    if (!g_state.initialized || !g_state.params) {
        return 0;
    }
    return g_state.params->security_level;
}

const kaz_kem_params_t* kaz_kem_get_params(void)
{
    return g_state.params;
}

int kaz_kem_is_initialized(void)
{
    return g_state.initialized;
}

size_t kaz_kem_publickey_bytes(void)
{
    if (!g_state.params) return 0;
    return g_state.params->publickey_bytes * 2;
}

size_t kaz_kem_privatekey_bytes(void)
{
    if (!g_state.params) return 0;
    return g_state.params->privatekey_bytes * 2;
}

size_t kaz_kem_ciphertext_bytes(void)
{
    if (!g_state.params) return 0;
    return g_state.params->general_bytes + (g_state.params->ephemeral_public_bytes * 2);
}

size_t kaz_kem_shared_secret_bytes(void)
{
    if (!g_state.params) return 0;
    return g_state.params->general_bytes;
}

void kaz_kem_cleanup(void)
{
    kaz_kem_clear_state();
}

/**
 * Full cleanup including OpenSSL internal state.
 * Call only at program exit - OpenSSL cannot be used after this.
 */
void kaz_kem_cleanup_full(void)
{
    kaz_kem_clear_state();
    /* Clear OpenSSL error queue */
    ERR_clear_error();
    /* Full OpenSSL cleanup - releases all internal allocations */
    OPENSSL_cleanup();
}

/**
 * Get version string at runtime.
 * This is an exported version of the inline function for shared library use.
 */
const char* kaz_kem_version(void)
{
#ifdef KAZ_KEM_VERSION
    return KAZ_KEM_VERSION;
#else
    return "2.0.0";
#endif
}

/* ============================================================================
 * Helper Functions
 * ============================================================================ */

/**
 * Perform constant-time modular exponentiation.
 */
static int ct_mod_exp(BIGNUM *result, const BIGNUM *base, const BIGNUM *exp,
                      const BIGNUM *mod, BN_CTX *ctx, BN_MONT_CTX *mont)
{
    return BN_mod_exp_mont_consttime(result, base, exp, mod, ctx, mont);
}

/**
 * Export BIGNUM to big-endian byte array with fixed size and padding.
 */
static int bn_to_bytes_padded(const BIGNUM *bn, unsigned char *out, size_t out_len)
{
    int bn_bytes = BN_num_bytes(bn);

    memset(out, 0, out_len);

    if (bn_bytes > (int)out_len) {
        return KAZ_KEM_ERROR_INVALID_PARAM;
    }

    if (BN_bn2bin(bn, out + (out_len - bn_bytes)) != bn_bytes) {
        return KAZ_KEM_ERROR_OPENSSL;
    }

    return KAZ_KEM_SUCCESS;
}

/**
 * Import big-endian byte array to BIGNUM.
 */
static BIGNUM *bytes_to_bn(const unsigned char *in, size_t in_len)
{
    return BN_bin2bn(in, (int)in_len, NULL);
}

/* ============================================================================
 * Core KEM Operations (Runtime API)
 * ============================================================================ */

int kaz_kem_keypair(unsigned char *pk, unsigned char *sk)
{
    int ret = KAZ_KEM_ERROR_OPENSSL;
    BN_CTX *ctx = NULL;
    BIGNUM *a1 = NULL, *a2 = NULL;
    BIGNUM *e1 = NULL, *e2 = NULL;
    BIGNUM *tmp = NULL, *tmp2 = NULL;
    BIGNUM *lowerbound = NULL;

    if (!pk || !sk) {
        return KAZ_KEM_ERROR_INVALID_PARAM;
    }

    if (!g_state.initialized) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }

    const kaz_kem_params_t *p = g_state.params;

    ctx = BN_CTX_new();
    a1 = BN_secure_new();
    a2 = BN_secure_new();
    e1 = BN_new();
    e2 = BN_new();
    tmp = BN_new();
    tmp2 = BN_new();
    lowerbound = BN_new();

    if (!ctx || !a1 || !a2 || !e1 || !e2 || !tmp || !tmp2 || !lowerbound) {
        ret = KAZ_KEM_ERROR_MEMORY;
        goto cleanup;
    }

    BN_set_flags(a1, BN_FLG_CONSTTIME);
    BN_set_flags(a2, BN_FLG_CONSTTIME);

    /* Generate a1 in range [2^(LOg1N-2), Og1N] */
    if (!BN_set_word(lowerbound, 1)) goto cleanup;
    if (!BN_lshift(lowerbound, lowerbound, p->LOg1N - 2)) goto cleanup;
    ret = kaz_kem_secure_random(lowerbound, g_state.Og1N, a1);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    /* Generate a2 in range [2^(LOg2N-2), Og2N] */
    if (!BN_set_word(lowerbound, 1)) goto cleanup;
    if (!BN_lshift(lowerbound, lowerbound, p->LOg2N - 2)) goto cleanup;
    ret = kaz_kem_secure_random(lowerbound, g_state.Og2N, a2);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    /* Compute e1 = g1^a1 * g2^(2*a2) mod N */
    if (!ct_mod_exp(e1, g_state.g1, a1, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_lshift1(tmp2, a2)) goto cleanup;
    if (!ct_mod_exp(tmp, g_state.g2, tmp2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(e1, e1, tmp, g_state.N, ctx)) goto cleanup;

    /* Compute e2 = g1^a2 * g2^a1 mod N */
    if (!ct_mod_exp(e2, g_state.g1, a2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!ct_mod_exp(tmp, g_state.g2, a1, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(e2, e2, tmp, g_state.N, ctx)) goto cleanup;

    /* Export public key: pk = e1 || e2 */
    ret = bn_to_bytes_padded(e1, pk, p->publickey_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;
    ret = bn_to_bytes_padded(e2, pk + p->publickey_bytes, p->publickey_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    /* Export private key: sk = a1 || a2 */
    ret = bn_to_bytes_padded(a1, sk, p->privatekey_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;
    ret = bn_to_bytes_padded(a2, sk + p->privatekey_bytes, p->privatekey_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    ret = KAZ_KEM_SUCCESS;

cleanup:
    BN_clear_free(a1);
    BN_clear_free(a2);
    BN_clear_free(e1);
    BN_clear_free(e2);
    BN_clear_free(tmp);
    BN_clear_free(tmp2);
    BN_clear_free(lowerbound);
    if (ctx) BN_CTX_free(ctx);

    return ret;
}

int kaz_kem_encapsulate(unsigned char *ct, unsigned long long *ctlen,
                        const unsigned char *ss, unsigned long long sslen,
                        const unsigned char *pk)
{
    int ret = KAZ_KEM_ERROR_OPENSSL;
    BN_CTX *ctx = NULL;
    BIGNUM *e1 = NULL, *e2 = NULL;
    BIGNUM *b1 = NULL, *b2 = NULL;
    BIGNUM *B1 = NULL, *B2 = NULL;
    BIGNUM *M = NULL, *ENCAP = NULL;
    BIGNUM *tmp = NULL, *tmp2 = NULL;
    BIGNUM *lowerbound = NULL;

    if (!ct || !ctlen || !ss || !pk) {
        return KAZ_KEM_ERROR_INVALID_PARAM;
    }

    if (!g_state.initialized) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }

    const kaz_kem_params_t *p = g_state.params;

    ctx = BN_CTX_new();
    /* e1, e2, M are assigned by bytes_to_bn() below — no pre-alloc needed */
    b1 = BN_secure_new();
    b2 = BN_secure_new();
    B1 = BN_new();
    B2 = BN_new();
    ENCAP = BN_new();
    tmp = BN_new();
    tmp2 = BN_new();
    lowerbound = BN_new();

    if (!ctx || !b1 || !b2 || !B1 || !B2 || !ENCAP ||
        !tmp || !tmp2 || !lowerbound) {
        ret = KAZ_KEM_ERROR_MEMORY;
        goto cleanup;
    }

    BN_set_flags(b1, BN_FLG_CONSTTIME);
    BN_set_flags(b2, BN_FLG_CONSTTIME);

    /* Import public key */
    e1 = bytes_to_bn(pk, p->publickey_bytes);
    e2 = bytes_to_bn(pk + p->publickey_bytes, p->publickey_bytes);
    if (!e1 || !e2) {
        ret = KAZ_KEM_ERROR_OPENSSL;
        goto cleanup;
    }

    /* Import message */
    M = bytes_to_bn(ss, p->general_bytes);
    if (!M) {
        ret = KAZ_KEM_ERROR_OPENSSL;
        goto cleanup;
    }

    /* Validate M < N */
    if (BN_cmp(M, g_state.N) >= 0) {
        fprintf(stderr, "KAZ-KEM-ENCAPSULATION ERROR: Message value >= modulus N\n");
        fprintf(stderr, "This message cannot be correctly encrypted/decrypted.\n");
        fprintf(stderr, "Message must be < N for correct operation.\n");
        ret = KAZ_KEM_ERROR_MSG_TOO_LARGE;
        goto cleanup;
    }

    /* Generate b1 in range [2^(LOg1N-2), Og1N] */
    if (!BN_set_word(lowerbound, 1)) goto cleanup;
    if (!BN_lshift(lowerbound, lowerbound, p->LOg1N - 2)) goto cleanup;
    ret = kaz_kem_secure_random(lowerbound, g_state.Og1N, b1);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    /* Generate b2 in range [2^(LOg2N-2), Og2N] */
    if (!BN_set_word(lowerbound, 1)) goto cleanup;
    if (!BN_lshift(lowerbound, lowerbound, p->LOg2N - 2)) goto cleanup;
    ret = kaz_kem_secure_random(lowerbound, g_state.Og2N, b2);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    /* Compute B1 = g1^b1 * g2^b2 mod N */
    if (!ct_mod_exp(B1, g_state.g1, b1, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!ct_mod_exp(tmp, g_state.g2, b2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(B1, B1, tmp, g_state.N, ctx)) goto cleanup;

    /* Compute B2 = g1^b2 * g2^(2*b1) mod N */
    if (!ct_mod_exp(B2, g_state.g1, b2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_lshift1(tmp2, b1)) goto cleanup;
    if (!ct_mod_exp(tmp, g_state.g2, tmp2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(B2, B2, tmp, g_state.N, ctx)) goto cleanup;

    /* Compute ENCAP = e1^b1 * e2^b2 + M mod N */
    if (!ct_mod_exp(ENCAP, e1, b1, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!ct_mod_exp(tmp, e2, b2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(ENCAP, ENCAP, tmp, g_state.N, ctx)) goto cleanup;
    if (!BN_mod_add(ENCAP, ENCAP, M, g_state.N, ctx)) goto cleanup;

    /* Export ciphertext: ct = ENCAP || B1 || B2 */
    ret = bn_to_bytes_padded(ENCAP, ct, p->general_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;
    ret = bn_to_bytes_padded(B1, ct + p->general_bytes, p->ephemeral_public_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;
    ret = bn_to_bytes_padded(B2, ct + p->general_bytes + p->ephemeral_public_bytes,
                             p->ephemeral_public_bytes);
    if (ret != KAZ_KEM_SUCCESS) goto cleanup;

    *ctlen = p->general_bytes + (p->ephemeral_public_bytes * 2);
    ret = KAZ_KEM_SUCCESS;

cleanup:
    BN_clear_free(e1);
    BN_clear_free(e2);
    BN_clear_free(b1);
    BN_clear_free(b2);
    BN_clear_free(B1);
    BN_clear_free(B2);
    BN_clear_free(M);
    BN_clear_free(ENCAP);
    BN_clear_free(tmp);
    BN_clear_free(tmp2);
    BN_clear_free(lowerbound);
    if (ctx) BN_CTX_free(ctx);

    return ret;
}

int kaz_kem_decapsulate(unsigned char *ss, unsigned long long *sslen,
                        const unsigned char *ct, unsigned long long ctlen,
                        const unsigned char *sk)
{
    int ret = KAZ_KEM_ERROR_OPENSSL;
    BN_CTX *ctx = NULL;
    BIGNUM *a1 = NULL, *a2 = NULL;
    BIGNUM *B1 = NULL, *B2 = NULL;
    BIGNUM *ENCAP = NULL, *DECAP = NULL;
    BIGNUM *tmp = NULL;

    if (!ss || !sslen || !ct || !sk) {
        return KAZ_KEM_ERROR_INVALID_PARAM;
    }

    if (!g_state.initialized) {
        return KAZ_KEM_ERROR_NOT_INIT;
    }

    const kaz_kem_params_t *p = g_state.params;

    /* Validate ciphertext length: ENCAP || B1 || B2 */
    size_t expected_ctlen = p->general_bytes + 2 * p->ephemeral_public_bytes;
    if ((size_t)ctlen < expected_ctlen) {
        return KAZ_KEM_ERROR_INVALID_PARAM;
    }

    ctx = BN_CTX_new();
    /* a1, a2 use secure memory for private key material */
    a1 = BN_secure_new();
    a2 = BN_secure_new();
    /* ENCAP, B1, B2 are assigned by bytes_to_bn() below — no pre-alloc */
    DECAP = BN_new();
    tmp = BN_new();

    if (!ctx || !a1 || !a2 || !DECAP || !tmp) {
        ret = KAZ_KEM_ERROR_MEMORY;
        goto cleanup;
    }

    /* Import private key into pre-allocated secure BIGNUMs */
    if (!BN_bin2bn(sk, (int)p->privatekey_bytes, a1) ||
        !BN_bin2bn(sk + p->privatekey_bytes, (int)p->privatekey_bytes, a2)) {
        ret = KAZ_KEM_ERROR_OPENSSL;
        goto cleanup;
    }
    BN_set_flags(a1, BN_FLG_CONSTTIME);
    BN_set_flags(a2, BN_FLG_CONSTTIME);

    /* Import ciphertext: ENCAP || B1 || B2 */
    ENCAP = bytes_to_bn(ct, p->general_bytes);
    B1 = bytes_to_bn(ct + p->general_bytes, p->ephemeral_public_bytes);
    B2 = bytes_to_bn(ct + p->general_bytes + p->ephemeral_public_bytes,
                     p->ephemeral_public_bytes);
    if (!ENCAP || !B1 || !B2) {
        ret = KAZ_KEM_ERROR_OPENSSL;
        goto cleanup;
    }

    /* Compute DECAP = ENCAP - (B1^a1 * B2^a2) mod N */
    if (!ct_mod_exp(DECAP, B1, a1, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!ct_mod_exp(tmp, B2, a2, g_state.N, ctx, g_state.mont_ctx)) goto cleanup;
    if (!BN_mod_mul(DECAP, DECAP, tmp, g_state.N, ctx)) goto cleanup;
    if (!BN_mod_sub(DECAP, ENCAP, DECAP, g_state.N, ctx)) goto cleanup;

    /* Export decapsulated message */
    memset(ss, 0, p->general_bytes);
    int bn_bytes = BN_num_bytes(DECAP);
    if (bn_bytes > 0 && bn_bytes <= (int)p->general_bytes) {
        if (BN_bn2bin(DECAP, ss + (p->general_bytes - bn_bytes)) != bn_bytes) {
            ret = KAZ_KEM_ERROR_OPENSSL;
            goto cleanup;
        }
    }

    *sslen = p->general_bytes;
    ret = KAZ_KEM_SUCCESS;

cleanup:
    BN_clear_free(a1);
    BN_clear_free(a2);
    BN_clear_free(B1);
    BN_clear_free(B2);
    BN_clear_free(ENCAP);
    BN_clear_free(DECAP);
    BN_clear_free(tmp);
    if (ctx) BN_CTX_free(ctx);

    return ret;
}

/* ============================================================================
 * KazWire Encoding/Decoding
 * ============================================================================ */

/**
 * Map security level to wire algorithm ID.
 */
static int kem_level_to_alg_id(int level)
{
    switch (level) {
        case 128: return KAZ_KEM_WIRE_128;
        case 192: return KAZ_KEM_WIRE_192;
        case 256: return KAZ_KEM_WIRE_256;
        default:  return -1;
    }
}

/**
 * Map wire algorithm ID to security level.
 */
static int kem_alg_id_to_level(int alg_id)
{
    switch (alg_id) {
        case KAZ_KEM_WIRE_128: return 128;
        case KAZ_KEM_WIRE_192: return 192;
        case KAZ_KEM_WIRE_256: return 256;
        default:               return -1;
    }
}

/**
 * Get expected key sizes for a given level.
 */
static const kaz_kem_params_t* kem_params_for_level(int level)
{
    switch (level) {
        case 128: return &KAZ_KEM_PARAMS_128;
        case 192: return &KAZ_KEM_PARAMS_192;
        case 256: return &KAZ_KEM_PARAMS_256;
        default:  return NULL;
    }
}

int kaz_kem_pubkey_to_wire(int level,
                            const unsigned char *pk, size_t pk_len,
                            unsigned char *out, size_t *out_len)
{
    if (!pk || !out || !out_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    int alg_id = kem_level_to_alg_id(level);
    if (alg_id < 0)
        return KAZ_KEM_ERROR_INVALID_LEVEL;

    const kaz_kem_params_t *p = kem_params_for_level(level);
    size_t expected = p->publickey_bytes * 2;
    if (pk_len != expected)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    size_t total = KAZ_KEM_WIRE_HEADER + pk_len;
    if (*out_len < total)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    out[0] = KAZ_KEM_WIRE_MAGIC_HI;
    out[1] = KAZ_KEM_WIRE_MAGIC_LO;
    out[2] = (unsigned char)alg_id;
    out[3] = KAZ_KEM_WIRE_TYPE_PUB;
    out[4] = KAZ_KEM_WIRE_VERSION;
    memcpy(out + KAZ_KEM_WIRE_HEADER, pk, pk_len);
    *out_len = total;

    return KAZ_KEM_SUCCESS;
}

int kaz_kem_pubkey_from_wire(const unsigned char *wire, size_t wire_len,
                              int *level,
                              unsigned char *pk, size_t *pk_len)
{
    if (!wire || !level || !pk || !pk_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    if (wire_len < KAZ_KEM_WIRE_HEADER)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[0] != KAZ_KEM_WIRE_MAGIC_HI || wire[1] != KAZ_KEM_WIRE_MAGIC_LO)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[3] != KAZ_KEM_WIRE_TYPE_PUB)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[4] != KAZ_KEM_WIRE_VERSION)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    int decoded_level = kem_alg_id_to_level(wire[2]);
    if (decoded_level < 0)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    const kaz_kem_params_t *p = kem_params_for_level(decoded_level);
    size_t key_len = p->publickey_bytes * 2;

    if (wire_len != KAZ_KEM_WIRE_HEADER + key_len)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (*pk_len < key_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    *level = decoded_level;
    memcpy(pk, wire + KAZ_KEM_WIRE_HEADER, key_len);
    *pk_len = key_len;

    return KAZ_KEM_SUCCESS;
}

int kaz_kem_privkey_to_wire(int level,
                             const unsigned char *sk, size_t sk_len,
                             unsigned char *out, size_t *out_len)
{
    if (!sk || !out || !out_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    int alg_id = kem_level_to_alg_id(level);
    if (alg_id < 0)
        return KAZ_KEM_ERROR_INVALID_LEVEL;

    const kaz_kem_params_t *p = kem_params_for_level(level);
    size_t expected = p->privatekey_bytes * 2;
    if (sk_len != expected)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    size_t total = KAZ_KEM_WIRE_HEADER + sk_len;
    if (*out_len < total)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    out[0] = KAZ_KEM_WIRE_MAGIC_HI;
    out[1] = KAZ_KEM_WIRE_MAGIC_LO;
    out[2] = (unsigned char)alg_id;
    out[3] = KAZ_KEM_WIRE_TYPE_PRIV;
    out[4] = KAZ_KEM_WIRE_VERSION;
    memcpy(out + KAZ_KEM_WIRE_HEADER, sk, sk_len);
    *out_len = total;

    return KAZ_KEM_SUCCESS;
}

int kaz_kem_privkey_from_wire(const unsigned char *wire, size_t wire_len,
                               int *level,
                               unsigned char *sk, size_t *sk_len)
{
    if (!wire || !level || !sk || !sk_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    if (wire_len < KAZ_KEM_WIRE_HEADER)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[0] != KAZ_KEM_WIRE_MAGIC_HI || wire[1] != KAZ_KEM_WIRE_MAGIC_LO)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[3] != KAZ_KEM_WIRE_TYPE_PRIV)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (wire[4] != KAZ_KEM_WIRE_VERSION)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    int decoded_level = kem_alg_id_to_level(wire[2]);
    if (decoded_level < 0)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    const kaz_kem_params_t *p = kem_params_for_level(decoded_level);
    size_t key_len = p->privatekey_bytes * 2;

    if (wire_len != KAZ_KEM_WIRE_HEADER + key_len)
        return KAZ_KEM_ERROR_WIRE_FORMAT;

    if (*sk_len < key_len)
        return KAZ_KEM_ERROR_INVALID_PARAM;

    *level = decoded_level;
    memcpy(sk, wire + KAZ_KEM_WIRE_HEADER, key_len);
    *sk_len = key_len;

    return KAZ_KEM_SUCCESS;
}

/* ============================================================================
 * BACKWARD COMPATIBILITY API (Compile-time Security Level)
 * These functions auto-initialize with KAZ_SECURITY_LEVEL if defined.
 * ============================================================================ */

#ifdef KAZ_SECURITY_LEVEL

int KAZ_KEM_KEYGEN(unsigned char *pk, unsigned char *sk)
{
    /* Auto-initialize with compile-time level if not already initialized */
    if (!g_state.initialized) {
        int ret = kaz_kem_init(KAZ_SECURITY_LEVEL);
        if (ret != KAZ_KEM_SUCCESS) return ret;
    }
    return kaz_kem_keypair(pk, sk);
}

int KAZ_KEM_ENCAPSULATION(unsigned char *encap, unsigned long long *encaplen,
                          const unsigned char *m, unsigned long long mlen,
                          const unsigned char *pk)
{
    if (!g_state.initialized) {
        int ret = kaz_kem_init(KAZ_SECURITY_LEVEL);
        if (ret != KAZ_KEM_SUCCESS) return ret;
    }
    return kaz_kem_encapsulate(encap, encaplen, m, mlen, pk);
}

int KAZ_KEM_DECAPSULATION(unsigned char *decap, unsigned long long *decaplen,
                          const unsigned char *encap, unsigned long long encaplen_in,
                          const unsigned char *sk)
{
    if (!g_state.initialized) {
        int ret = kaz_kem_init(KAZ_SECURITY_LEVEL);
        if (ret != KAZ_KEM_SUCCESS) return ret;
    }
    return kaz_kem_decapsulate(decap, decaplen, encap, encaplen_in, sk);
}

void KAZ_KEM_CLEANUP(void)
{
    kaz_kem_cleanup();
}

#endif /* KAZ_SECURITY_LEVEL */
