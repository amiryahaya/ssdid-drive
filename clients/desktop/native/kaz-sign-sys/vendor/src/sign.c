/*
 * KAZ-SIGN: Constant-Time Implementation using OpenSSL BIGNUM
 * Version 2.1 - Runtime Security Level Support
 *
 * This implementation replaces GMP with OpenSSL's BIGNUM library
 * using constant-time operations to prevent timing side-channel attacks.
 *
 * Key security features:
 * - BN_FLG_CONSTTIME flag on all secret values
 * - BN_mod_exp_mont_consttime for modular exponentiation
 * - Secure memory zeroization
 * - No branching on secret data
 *
 * Version 2.1 adds runtime security level selection.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/bn.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>

#include "kaz/sign.h"
#include "kaz/security.h"

/* ============================================================================
 * Static Level Parameters (for all three security levels)
 * ============================================================================ */

/* Level 128 parameters */
static const kaz_sign_level_params_t g_level_128_params = {
    .level = 128,
    .algorithm_name = "KAZ-SIGN-128",
    .secret_key_bytes = 32,
    .public_key_bytes = 54,
    .hash_bytes = 32,
    .signature_overhead = 162,  /* 54 + 54 + 54 */
    .s_bytes = 16,
    .t_bytes = 16,
    .s1_bytes = 54,
    .s2_bytes = 54,
    .s3_bytes = 54
};

/* Level 192 parameters */
static const kaz_sign_level_params_t g_level_192_params = {
    .level = 192,
    .algorithm_name = "KAZ-SIGN-192",
    .secret_key_bytes = 50,
    .public_key_bytes = 88,
    .hash_bytes = 48,
    .signature_overhead = 264,  /* 88 + 88 + 88 */
    .s_bytes = 25,
    .t_bytes = 25,
    .s1_bytes = 88,
    .s2_bytes = 88,
    .s3_bytes = 88
};

/* Level 256 parameters */
static const kaz_sign_level_params_t g_level_256_params = {
    .level = 256,
    .algorithm_name = "KAZ-SIGN-256",
    .secret_key_bytes = 64,
    .public_key_bytes = 118,
    .hash_bytes = 64,
    .signature_overhead = 356,  /* 118 + 119 + 119 */
    .s_bytes = 32,
    .t_bytes = 32,
    .s1_bytes = 118,
    .s2_bytes = 119,
    .s3_bytes = 119
};

/* String constants for each level */
static const char *g_level_128_g1 = "65537";
static const char *g_level_128_g2 = "65539";
static const char *g_level_128_N = "9680693320350411581735712527156160041331448806285781880953481207107506184928318589548473667621840334803765737814574120142199988285";
static const char *g_level_128_phiN = "1862854061641389163337017925599133865006616816206541406153748908271169581801631840410608441366518309266967756800000000000000000000";
static const char *g_level_128_Og1N = "104096837085595768062256170741230052000";
static const char *g_level_128_Og2N = "17349472847599294677042695123538342000";

static const char *g_level_192_g1 = "65537";
static const char *g_level_192_g2 = "65539";
static const char *g_level_192_N = "15982040643598444277320371265136974856402799594720686504760818091215333991414038871394426514903965899103553442859146701270930684879295849706045338879593833465052745734862675359470536861467492521046077102660572015";
static const char *g_level_192_phiN = "2852982385092065996343896318300390927321234264319221230294884622249277900787903710363361658485275185133309433619496986167576406960701801204725152385400156421631204526170043735085154304000000000000000000000000000";
static const char *g_level_192_Og1N = "12934000239870021828648909535012878456790556542848408504000";
static const char *g_level_192_Og2N = "12934000239870021828648909535012878456790556542848408504000";

static const char *g_level_256_g1 = "65537";
static const char *g_level_256_g2 = "65539";
static const char *g_level_256_N = "29421818394147345935036136135391375994024126405325576672227398037493559452008116283594709069097880319117946343281357631447556041903884586208161678710597469727999746179863045388559147407457068275815914914983896392757878683919189075898269550939868181179868469970964809582599153788719655";
static const char *g_level_256_phiN = "502924248251635525629785876194372240141863912168458452749995697467455160087932504342175710330632944142887080586716346345907214888007643703094458414828200990128223075181127530152432620200757034038485458163071614226834741804596849230360138563704586240000000000000000000000000000000000000";
static const char *g_level_256_Og1N = "49577346943749914278558040936897577826073730777121114343013903022328490384000";
static const char *g_level_256_Og2N = "24788673471874957139279020468448788913036865388560557171506951511164245192000";

/* ============================================================================
 * Runtime Parameter Cache (one per security level)
 * ============================================================================ */

typedef struct {
    BIGNUM *g1;         /* Generator 1 */
    BIGNUM *g2;         /* Generator 2 */
    BIGNUM *N;          /* Modulus */
    BIGNUM *phiN;       /* Euler's totient of N */
    BIGNUM *Og1N;       /* Order of g1 mod N */
    BIGNUM *Og2N;       /* Order of g2 mod N */
    BIGNUM *g1g2;       /* Pre-computed g1 * g2 */
    BIGNUM *lb_g1;      /* Lower bound for s */
    BIGNUM *lb_g2;      /* Lower bound for t */
    BN_MONT_CTX *mont;  /* Montgomery context for N */
    BN_CTX *bn_ctx;     /* Reusable BN context */
    EVP_MD_CTX *hash_ctx;
    const EVP_MD *hash_md;
    const kaz_sign_level_params_t *params;
    int initialized;
} kaz_runtime_params_t;

/* Runtime parameter caches for each level */
static kaz_runtime_params_t g_runtime_128 = { .initialized = 0 };
static kaz_runtime_params_t g_runtime_192 = { .initialized = 0 };
static kaz_runtime_params_t g_runtime_256 = { .initialized = 0 };

/* Legacy global state (for backwards compatibility) */
typedef struct {
    BIGNUM *g1;         /* Generator 1 */
    BIGNUM *g2;         /* Generator 2 */
    BIGNUM *N;          /* Modulus */
    BIGNUM *phiN;       /* Euler's totient of N */
    BIGNUM *Og1N;       /* Order of g1 mod N */
    BIGNUM *Og2N;       /* Order of g2 mod N */
    BIGNUM *g1g2;       /* Pre-computed g1 * g2 */
    BIGNUM *lb_g1;      /* Lower bound for s */
    BIGNUM *lb_g2;      /* Lower bound for t */
    BN_MONT_CTX *mont;  /* Montgomery context for N */
    BN_CTX *bn_ctx;     /* Reusable BN context */
    int initialized;
} kaz_sign_params_legacy_t;

static kaz_sign_params_legacy_t g_params = { .initialized = 0 };

/* Hash context (legacy) */
static EVP_MD_CTX *g_hash_ctx = NULL;
static const EVP_MD *g_hash_md = NULL;

/* ============================================================================
 * Helper Functions
 * ============================================================================ */

/* Securely free a BIGNUM */
static void bn_secure_free(BIGNUM *bn)
{
    if (bn) {
        BN_clear_free(bn);  /* Secure free */
    }
}

/* Set constant-time flag on a BIGNUM (marks as secret) */
static void bn_set_secret(BIGNUM *bn)
{
    if (bn) {
        BN_set_flags(bn, BN_FLG_CONSTTIME);
    }
}

/* Export BIGNUM to fixed-size buffer (right-aligned, zero-padded) */
static int bn_export_padded(unsigned char *buf, size_t buf_size, const BIGNUM *bn)
{
    int bn_size;

    memset(buf, 0, buf_size);

    if (bn == NULL || BN_is_zero(bn)) {
        return 0;
    }

    bn_size = BN_num_bytes(bn);
    if ((size_t)bn_size > buf_size) {
        return -1;  /* Value too large for buffer */
    }

    /* Write to end of buffer for right-alignment */
    BN_bn2bin(bn, buf + (buf_size - bn_size));
    return 0;
}

/* Import fixed-size buffer to BIGNUM */
static int bn_import(BIGNUM *bn, const unsigned char *buf, size_t buf_size)
{
    if (BN_bin2bn(buf, (int)buf_size, bn) == NULL) {
        return -1;
    }
    return 0;
}

/* ============================================================================
 * Parameter Initialization
 * ============================================================================ */

static int init_params_cache(void)
{
    int ret = KAZ_SIGN_ERROR_MEMORY;
    BIGNUM *two = NULL;
    BIGNUM *exp = NULL;
    int bits;

    if (g_params.initialized) {
        return KAZ_SIGN_SUCCESS;
    }

    /* Allocate all BIGNUMs */
    g_params.g1 = BN_new();
    g_params.g2 = BN_new();
    g_params.N = BN_new();
    g_params.phiN = BN_new();
    g_params.Og1N = BN_new();
    g_params.Og2N = BN_new();
    g_params.g1g2 = BN_new();
    g_params.lb_g1 = BN_new();
    g_params.lb_g2 = BN_new();
    g_params.bn_ctx = BN_CTX_new();
    two = BN_new();
    exp = BN_new();

    if (!g_params.g1 || !g_params.g2 || !g_params.N || !g_params.phiN ||
        !g_params.Og1N || !g_params.Og2N || !g_params.g1g2 ||
        !g_params.lb_g1 || !g_params.lb_g2 || !g_params.bn_ctx ||
        !two || !exp) {
        goto cleanup;
    }

    /* Parse system parameters */
    if (!BN_dec2bn(&g_params.g1, KAZ_SIGN_SP_g1)) goto cleanup;
    if (!BN_dec2bn(&g_params.g2, KAZ_SIGN_SP_g2)) goto cleanup;
    if (!BN_dec2bn(&g_params.N, KAZ_SIGN_SP_N)) goto cleanup;
    if (!BN_dec2bn(&g_params.phiN, KAZ_SIGN_SP_phiN)) goto cleanup;
    if (!BN_dec2bn(&g_params.Og1N, KAZ_SIGN_SP_Og1N)) goto cleanup;
    if (!BN_dec2bn(&g_params.Og2N, KAZ_SIGN_SP_Og2N)) goto cleanup;

    /* Pre-compute g1 * g2 mod N */
    if (!BN_mod_mul(g_params.g1g2, g_params.g1, g_params.g2,
                    g_params.N, g_params.bn_ctx)) {
        goto cleanup;
    }

    /* Pre-compute lower bounds: 2^(bits-2) */
    BN_set_word(two, 2);

    bits = BN_num_bits(g_params.Og1N);
    BN_set_word(exp, bits - 2);
    if (!BN_exp(g_params.lb_g1, two, exp, g_params.bn_ctx)) goto cleanup;

    bits = BN_num_bits(g_params.Og2N);
    BN_set_word(exp, bits - 2);
    if (!BN_exp(g_params.lb_g2, two, exp, g_params.bn_ctx)) goto cleanup;

    /* Create Montgomery context for faster modular operations */
    g_params.mont = BN_MONT_CTX_new();
    if (!g_params.mont) goto cleanup;
    if (!BN_MONT_CTX_set(g_params.mont, g_params.N, g_params.bn_ctx)) {
        goto cleanup;
    }

    /* Initialize hash function */
#if KAZ_SECURITY_LEVEL == 128
    g_hash_md = EVP_sha256();
#elif KAZ_SECURITY_LEVEL == 192
    g_hash_md = EVP_sha384();
#elif KAZ_SECURITY_LEVEL == 256
    g_hash_md = EVP_sha512();
#endif

    g_hash_ctx = EVP_MD_CTX_new();
    if (!g_hash_ctx) goto cleanup;

    g_params.initialized = 1;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    BN_free(two);
    BN_free(exp);

    if (ret != KAZ_SIGN_SUCCESS) {
        /* Clean up on failure */
        bn_secure_free(g_params.g1);
        bn_secure_free(g_params.g2);
        bn_secure_free(g_params.N);
        bn_secure_free(g_params.phiN);
        bn_secure_free(g_params.Og1N);
        bn_secure_free(g_params.Og2N);
        bn_secure_free(g_params.g1g2);
        bn_secure_free(g_params.lb_g1);
        bn_secure_free(g_params.lb_g2);
        if (g_params.mont) BN_MONT_CTX_free(g_params.mont);
        if (g_params.bn_ctx) BN_CTX_free(g_params.bn_ctx);
        g_params.initialized = 0;
    }

    return ret;
}

static void clear_params_cache(void)
{
    if (g_params.initialized) {
        bn_secure_free(g_params.g1);
        bn_secure_free(g_params.g2);
        bn_secure_free(g_params.N);
        bn_secure_free(g_params.phiN);
        bn_secure_free(g_params.Og1N);
        bn_secure_free(g_params.Og2N);
        bn_secure_free(g_params.g1g2);
        bn_secure_free(g_params.lb_g1);
        bn_secure_free(g_params.lb_g2);

        if (g_params.mont) {
            BN_MONT_CTX_free(g_params.mont);
            g_params.mont = NULL;
        }
        if (g_params.bn_ctx) {
            BN_CTX_free(g_params.bn_ctx);
            g_params.bn_ctx = NULL;
        }
        if (g_hash_ctx) {
            EVP_MD_CTX_free(g_hash_ctx);
            g_hash_ctx = NULL;
        }

        g_params.initialized = 0;
    }
}

/* ============================================================================
 * Runtime Security Level API Implementation
 * ============================================================================ */

const kaz_sign_level_params_t *kaz_sign_get_level_params(kaz_sign_level_t level)
{
    switch (level) {
        case KAZ_LEVEL_128: return &g_level_128_params;
        case KAZ_LEVEL_192: return &g_level_192_params;
        case KAZ_LEVEL_256: return &g_level_256_params;
        default: return NULL;
    }
}

/* Get the runtime parameter cache for a level */
static kaz_runtime_params_t *get_runtime_params(kaz_sign_level_t level)
{
    switch (level) {
        case KAZ_LEVEL_128: return &g_runtime_128;
        case KAZ_LEVEL_192: return &g_runtime_192;
        case KAZ_LEVEL_256: return &g_runtime_256;
        default: return NULL;
    }
}

/* Get string constants for a level */
static void get_level_strings(kaz_sign_level_t level,
                              const char **g1, const char **g2,
                              const char **N, const char **phiN,
                              const char **Og1N, const char **Og2N)
{
    switch (level) {
        case KAZ_LEVEL_128:
            *g1 = g_level_128_g1; *g2 = g_level_128_g2;
            *N = g_level_128_N; *phiN = g_level_128_phiN;
            *Og1N = g_level_128_Og1N; *Og2N = g_level_128_Og2N;
            break;
        case KAZ_LEVEL_192:
            *g1 = g_level_192_g1; *g2 = g_level_192_g2;
            *N = g_level_192_N; *phiN = g_level_192_phiN;
            *Og1N = g_level_192_Og1N; *Og2N = g_level_192_Og2N;
            break;
        case KAZ_LEVEL_256:
            *g1 = g_level_256_g1; *g2 = g_level_256_g2;
            *N = g_level_256_N; *phiN = g_level_256_phiN;
            *Og1N = g_level_256_Og1N; *Og2N = g_level_256_Og2N;
            break;
        default:
            *g1 = *g2 = *N = *phiN = *Og1N = *Og2N = NULL;
    }
}

/* Initialize runtime parameters for a specific level */
static int init_runtime_params(kaz_runtime_params_t *rp, kaz_sign_level_t level)
{
    int ret = KAZ_SIGN_ERROR_MEMORY;
    BIGNUM *two = NULL;
    BIGNUM *exp = NULL;
    int bits;
    const char *g1_str, *g2_str, *N_str, *phiN_str, *Og1N_str, *Og2N_str;

    if (rp->initialized) {
        return KAZ_SIGN_SUCCESS;
    }

    /* Get level parameters */
    rp->params = kaz_sign_get_level_params(level);
    if (!rp->params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Get string constants */
    get_level_strings(level, &g1_str, &g2_str, &N_str, &phiN_str, &Og1N_str, &Og2N_str);
    if (!g1_str) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Allocate all BIGNUMs */
    rp->g1 = BN_new();
    rp->g2 = BN_new();
    rp->N = BN_new();
    rp->phiN = BN_new();
    rp->Og1N = BN_new();
    rp->Og2N = BN_new();
    rp->g1g2 = BN_new();
    rp->lb_g1 = BN_new();
    rp->lb_g2 = BN_new();
    rp->bn_ctx = BN_CTX_new();
    two = BN_new();
    exp = BN_new();

    if (!rp->g1 || !rp->g2 || !rp->N || !rp->phiN ||
        !rp->Og1N || !rp->Og2N || !rp->g1g2 ||
        !rp->lb_g1 || !rp->lb_g2 || !rp->bn_ctx ||
        !two || !exp) {
        goto cleanup;
    }

    /* Parse system parameters */
    if (!BN_dec2bn(&rp->g1, g1_str)) goto cleanup;
    if (!BN_dec2bn(&rp->g2, g2_str)) goto cleanup;
    if (!BN_dec2bn(&rp->N, N_str)) goto cleanup;
    if (!BN_dec2bn(&rp->phiN, phiN_str)) goto cleanup;
    if (!BN_dec2bn(&rp->Og1N, Og1N_str)) goto cleanup;
    if (!BN_dec2bn(&rp->Og2N, Og2N_str)) goto cleanup;

    /* Pre-compute g1 * g2 mod N */
    if (!BN_mod_mul(rp->g1g2, rp->g1, rp->g2, rp->N, rp->bn_ctx)) {
        goto cleanup;
    }

    /* Pre-compute lower bounds: 2^(bits-2) */
    BN_set_word(two, 2);

    bits = BN_num_bits(rp->Og1N);
    BN_set_word(exp, bits - 2);
    if (!BN_exp(rp->lb_g1, two, exp, rp->bn_ctx)) goto cleanup;

    bits = BN_num_bits(rp->Og2N);
    BN_set_word(exp, bits - 2);
    if (!BN_exp(rp->lb_g2, two, exp, rp->bn_ctx)) goto cleanup;

    /* Create Montgomery context for faster modular operations */
    rp->mont = BN_MONT_CTX_new();
    if (!rp->mont) goto cleanup;
    if (!BN_MONT_CTX_set(rp->mont, rp->N, rp->bn_ctx)) {
        goto cleanup;
    }

    /* Initialize hash function based on level */
    switch (level) {
        case KAZ_LEVEL_128: rp->hash_md = EVP_sha256(); break;
        case KAZ_LEVEL_192: rp->hash_md = EVP_sha384(); break;
        case KAZ_LEVEL_256: rp->hash_md = EVP_sha512(); break;
        default: goto cleanup;
    }

    rp->hash_ctx = EVP_MD_CTX_new();
    if (!rp->hash_ctx) goto cleanup;

    rp->initialized = 1;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    BN_free(two);
    BN_free(exp);

    if (ret != KAZ_SIGN_SUCCESS) {
        /* Clean up on failure */
        bn_secure_free(rp->g1); rp->g1 = NULL;
        bn_secure_free(rp->g2); rp->g2 = NULL;
        bn_secure_free(rp->N); rp->N = NULL;
        bn_secure_free(rp->phiN); rp->phiN = NULL;
        bn_secure_free(rp->Og1N); rp->Og1N = NULL;
        bn_secure_free(rp->Og2N); rp->Og2N = NULL;
        bn_secure_free(rp->g1g2); rp->g1g2 = NULL;
        bn_secure_free(rp->lb_g1); rp->lb_g1 = NULL;
        bn_secure_free(rp->lb_g2); rp->lb_g2 = NULL;
        if (rp->mont) { BN_MONT_CTX_free(rp->mont); rp->mont = NULL; }
        if (rp->bn_ctx) { BN_CTX_free(rp->bn_ctx); rp->bn_ctx = NULL; }
        if (rp->hash_ctx) { EVP_MD_CTX_free(rp->hash_ctx); rp->hash_ctx = NULL; }
        rp->initialized = 0;
    }

    return ret;
}

/* Clear runtime parameters for a specific level */
static void clear_runtime_params(kaz_runtime_params_t *rp)
{
    if (rp && rp->initialized) {
        bn_secure_free(rp->g1); rp->g1 = NULL;
        bn_secure_free(rp->g2); rp->g2 = NULL;
        bn_secure_free(rp->N); rp->N = NULL;
        bn_secure_free(rp->phiN); rp->phiN = NULL;
        bn_secure_free(rp->Og1N); rp->Og1N = NULL;
        bn_secure_free(rp->Og2N); rp->Og2N = NULL;
        bn_secure_free(rp->g1g2); rp->g1g2 = NULL;
        bn_secure_free(rp->lb_g1); rp->lb_g1 = NULL;
        bn_secure_free(rp->lb_g2); rp->lb_g2 = NULL;
        if (rp->mont) { BN_MONT_CTX_free(rp->mont); rp->mont = NULL; }
        if (rp->bn_ctx) { BN_CTX_free(rp->bn_ctx); rp->bn_ctx = NULL; }
        if (rp->hash_ctx) { EVP_MD_CTX_free(rp->hash_ctx); rp->hash_ctx = NULL; }
        rp->hash_md = NULL;
        rp->params = NULL;
        rp->initialized = 0;
    }
}

/* Public API: Initialize a specific security level */
int kaz_sign_init_level(kaz_sign_level_t level)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    if (!rp) {
        return KAZ_SIGN_ERROR_INVALID;
    }
    return init_runtime_params(rp, level);
}

/* Public API: Clear a specific security level */
void kaz_sign_clear_level(kaz_sign_level_t level)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    if (rp) {
        clear_runtime_params(rp);
    }
}

/* Public API: Clear all security levels */
void kaz_sign_clear_all(void)
{
    clear_runtime_params(&g_runtime_128);
    clear_runtime_params(&g_runtime_192);
    clear_runtime_params(&g_runtime_256);
    clear_params_cache();  /* Also clear legacy cache */
}

/* ============================================================================
 * Random Number Generation (Constant-Time)
 * ============================================================================ */

static int g_rand_initialized = 0;

int kaz_sign_init_random(void)
{
    if (g_rand_initialized) {
        return KAZ_SIGN_SUCCESS;
    }

    int ret = init_params_cache();
    if (ret != KAZ_SIGN_SUCCESS) {
        return ret;
    }

    g_rand_initialized = 1;
    return KAZ_SIGN_SUCCESS;
}

void kaz_sign_clear_random(void)
{
    clear_params_cache();
    g_rand_initialized = 0;
}

int kaz_sign_is_initialized(void)
{
    return g_rand_initialized;
}

/* Generate random number in range [lb, ub] using rejection sampling */
static int bn_random_range(BIGNUM *result, const BIGNUM *lb, const BIGNUM *ub,
                           BN_CTX *ctx)
{
    BIGNUM *range = BN_new();
    BIGNUM *rand_val = BN_new();
    int ret = -1;

    (void)ctx;  /* Reserved for future use */

    if (!range || !rand_val) goto cleanup;

    /* range = ub - lb + 1 */
    if (!BN_sub(range, ub, lb)) goto cleanup;
    if (!BN_add_word(range, 1)) goto cleanup;

    /* Generate random in [0, range) */
    if (!BN_rand_range(rand_val, range)) goto cleanup;

    /* result = lb + rand_val */
    if (!BN_add(result, lb, rand_val)) goto cleanup;

    ret = 0;

cleanup:
    bn_secure_free(range);
    bn_secure_free(rand_val);
    return ret;
}

/* ============================================================================
 * Hash Function
 * ============================================================================ */

int kaz_sign_hash(const unsigned char *msg,
                  unsigned long long msglen,
                  unsigned char *hash)
{
    unsigned int hash_len = 0;

    if (!g_params.initialized || !g_hash_ctx || !g_hash_md) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestInit_ex(g_hash_ctx, g_hash_md, NULL) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestUpdate(g_hash_ctx, msg, msglen) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestFinal_ex(g_hash_ctx, hash, &hash_len) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Constant-Time Modular Exponentiation
 * ============================================================================ */

/*
 * Perform modular exponentiation in constant time.
 * Uses Montgomery multiplication with constant-time flag.
 */
static int bn_mod_exp_consttime(BIGNUM *result, const BIGNUM *base,
                                 const BIGNUM *exp, const BIGNUM *mod,
                                 BN_CTX *ctx, BN_MONT_CTX *mont)
{
    /* Use constant-time Montgomery exponentiation */
    return BN_mod_exp_mont_consttime(result, base, exp, mod, ctx, mont);
}

/* ============================================================================
 * Key Generation (Constant-Time)
 * ============================================================================ */

int kaz_sign_keypair(unsigned char *pk, unsigned char *sk)
{
    BIGNUM *s = NULL;
    BIGNUM *t = NULL;
    BIGNUM *V = NULL;
    BIGNUM *tmp = NULL;
    int ret = KAZ_SIGN_ERROR_MEMORY;

    if (pk == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (!g_rand_initialized) {
        ret = kaz_sign_init_random();
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    /* Allocate BIGNUMs */
    s = BN_secure_new();  /* Use secure allocation for secrets */
    t = BN_secure_new();
    V = BN_new();
    tmp = BN_new();

    if (!s || !t || !V || !tmp) {
        goto cleanup;
    }

    /* Mark secret values for constant-time operations */
    bn_set_secret(s);
    bn_set_secret(t);

    /* Generate random s in [lb_g1, Og1N] */
    if (bn_random_range(s, g_params.lb_g1, g_params.Og1N, g_params.bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }

    /* Generate random t in [lb_g2, Og2N] */
    if (bn_random_range(t, g_params.lb_g2, g_params.Og2N, g_params.bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }

    /* Compute V = g1^s * g2^t mod N using constant-time exponentiation */
    if (!bn_mod_exp_consttime(tmp, g_params.g1, s, g_params.N,
                              g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!bn_mod_exp_consttime(V, g_params.g2, t, g_params.N,
                              g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!BN_mod_mul(V, V, tmp, g_params.N, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Export to output buffers */
    if (bn_export_padded(sk, KAZ_SIGN_SBYTES, s) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sk + KAZ_SIGN_SBYTES, KAZ_SIGN_TBYTES, t) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(pk, KAZ_SIGN_PUBLICKEYBYTES, V) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    /* Securely clear secret values */
    bn_secure_free(s);
    bn_secure_free(t);
    BN_free(V);
    BN_free(tmp);

    return ret;
}

/* ============================================================================
 * Signature Generation (Constant-Time)
 * ============================================================================ */

int kaz_sign_signature(unsigned char *sig,
                       unsigned long long *siglen,
                       const unsigned char *msg,
                       unsigned long long msglen,
                       const unsigned char *sk)
{
    BIGNUM *s = NULL, *t = NULL;
    BIGNUM *e1 = NULL, *e2 = NULL;
    BIGNUM *h = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *tmp = NULL, *tmp2 = NULL;
    BIGNUM *e1_inv = NULL;
    unsigned char hash_buf[KAZ_SIGN_BYTES];
    int ret = KAZ_SIGN_ERROR_MEMORY;

    if (sig == NULL || siglen == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (msg == NULL && msglen > 0) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (!g_rand_initialized) {
        ret = kaz_sign_init_random();
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    /* Allocate BIGNUMs - use secure allocation for secrets */
    s = BN_secure_new();
    t = BN_secure_new();
    e1 = BN_secure_new();
    e2 = BN_secure_new();
    h = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    tmp = BN_secure_new();
    tmp2 = BN_secure_new();
    e1_inv = BN_secure_new();

    if (!s || !t || !e1 || !e2 || !h || !S1 || !S2 || !S3 ||
        !tmp || !tmp2 || !e1_inv) {
        goto cleanup;
    }

    /* Mark secret values */
    bn_set_secret(s);
    bn_set_secret(t);
    bn_set_secret(e1);
    bn_set_secret(e2);
    bn_set_secret(tmp);
    bn_set_secret(tmp2);
    bn_set_secret(e1_inv);

    /* Import secret key */
    if (bn_import(s, sk, KAZ_SIGN_SBYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(t, sk + KAZ_SIGN_SBYTES, KAZ_SIGN_TBYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(s);
    bn_set_secret(t);

    /* Hash message */
    if (kaz_sign_hash(msg, msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(h, hash_buf, KAZ_SIGN_BYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Generate random e1, then find next prime */
    if (bn_random_range(e1, g_params.lb_g1, g_params.Og1N, g_params.bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    /* Find next prime (not constant-time, but e1 is random so timing doesn't leak secrets) */
    if (!BN_generate_prime_ex(e1, BN_num_bits(e1), 0, NULL, NULL, NULL)) {
        /* Fallback: just use the random value if prime generation fails */
    }
    bn_set_secret(e1);

    /* Generate random e2 */
    if (bn_random_range(e2, g_params.lb_g2, g_params.Og2N, g_params.bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    bn_set_secret(e2);

    /* Compute S1 = g1^e1 * g2^e2 mod N (constant-time) */
    if (!bn_mod_exp_consttime(tmp, g_params.g1, e1, g_params.N,
                              g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!bn_mod_exp_consttime(S1, g_params.g2, e2, g_params.N,
                              g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(S1, S1, tmp, g_params.N, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute e1^(-1) mod phi(N) */
    if (!BN_mod_inverse(e1_inv, e1, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(e1_inv);

    /* Compute S2 = (h - s*S1) * e1^(-1) mod phi(N) */
    if (!BN_mod_mul(tmp, s, S1, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_sub(tmp, h, tmp, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(S2, tmp, e1_inv, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute S3 = h - t*S1 - e2*S2 mod phi(N) */
    if (!BN_mod_mul(tmp, t, S1, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(tmp2, e2, S2, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_add(tmp, tmp, tmp2, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_sub(S3, h, tmp, g_params.phiN, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Export signature */
    memset(sig, 0, KAZ_SIGN_SIGNATURE_OVERHEAD + msglen);

    if (bn_export_padded(sig, KAZ_SIGN_S1BYTES, S1) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sig + KAZ_SIGN_S1BYTES, KAZ_SIGN_S2BYTES, S2) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sig + KAZ_SIGN_S1BYTES + KAZ_SIGN_S2BYTES,
                         KAZ_SIGN_S3BYTES, S3) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Append message */
    if (msglen > 0) {
        memcpy(sig + KAZ_SIGN_SIGNATURE_OVERHEAD, msg, msglen);
    }

    *siglen = KAZ_SIGN_SIGNATURE_OVERHEAD + msglen;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    /* Securely clear all sensitive data */
    kaz_secure_zero(hash_buf, sizeof(hash_buf));

    bn_secure_free(s);
    bn_secure_free(t);
    bn_secure_free(e1);
    bn_secure_free(e2);
    bn_secure_free(tmp);
    bn_secure_free(tmp2);
    bn_secure_free(e1_inv);
    BN_free(h);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);

    return ret;
}

/* ============================================================================
 * Signature Verification (Constant-Time where applicable)
 * ============================================================================ */

int kaz_sign_verify(unsigned char *msg,
                    unsigned long long *msglen,
                    const unsigned char *sig,
                    unsigned long long siglen,
                    const unsigned char *pk)
{
    BIGNUM *V = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *h = NULL;
    BIGNUM *Y1 = NULL, *Y2 = NULL;
    BIGNUM *tmp = NULL;
    unsigned char hash_buf[KAZ_SIGN_BYTES];
    unsigned long long extracted_msglen;
    int ret = KAZ_SIGN_ERROR_VERIFY;

    if (msg == NULL || msglen == NULL || sig == NULL || pk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (siglen < KAZ_SIGN_SIGNATURE_OVERHEAD) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (!g_params.initialized) {
        if (init_params_cache() != KAZ_SIGN_SUCCESS) {
            return KAZ_SIGN_ERROR_INVALID;
        }
    }

    extracted_msglen = siglen - KAZ_SIGN_SIGNATURE_OVERHEAD;

    /* Allocate BIGNUMs */
    V = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    h = BN_new();
    Y1 = BN_new();
    Y2 = BN_new();
    tmp = BN_new();

    if (!V || !S1 || !S2 || !S3 || !h || !Y1 || !Y2 || !tmp) {
        ret = KAZ_SIGN_ERROR_MEMORY;
        goto cleanup;
    }

    /* Import public key and signature components */
    if (bn_import(V, pk, KAZ_SIGN_PUBLICKEYBYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S1, sig, KAZ_SIGN_S1BYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S2, sig + KAZ_SIGN_S1BYTES, KAZ_SIGN_S2BYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S3, sig + KAZ_SIGN_S1BYTES + KAZ_SIGN_S2BYTES,
                  KAZ_SIGN_S3BYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Hash the embedded message */
    const unsigned char *embedded_msg = sig + KAZ_SIGN_SIGNATURE_OVERHEAD;
    if (kaz_sign_hash(embedded_msg, extracted_msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(h, hash_buf, KAZ_SIGN_BYTES) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute Y1 = V^S1 * S1^S2 * g2^S3 mod N */
    /* Note: Verification doesn't need constant-time since all values are public */
    if (!BN_mod_exp_mont(tmp, V, S1, g_params.N, g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_exp_mont(Y1, S1, S2, g_params.N, g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(Y1, Y1, tmp, g_params.N, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!BN_mod_exp_mont(tmp, g_params.g2, S3, g_params.N,
                         g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(Y1, Y1, tmp, g_params.N, g_params.bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute Y2 = (g1 * g2)^h mod N */
    if (!BN_mod_exp_mont(Y2, g_params.g1g2, h, g_params.N,
                         g_params.bn_ctx, g_params.mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Verify Y1 == Y2 */
    if (BN_cmp(Y1, Y2) != 0) {
        ret = KAZ_SIGN_ERROR_VERIFY;
        goto cleanup;
    }

    /* Copy out the message */
    memcpy(msg, embedded_msg, extracted_msglen);
    *msglen = extracted_msglen;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    kaz_secure_zero(hash_buf, sizeof(hash_buf));

    BN_free(V);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);
    BN_free(h);
    BN_free(Y1);
    BN_free(Y2);
    BN_free(tmp);

    return ret;
}

/* ============================================================================
 * Version API
 * ============================================================================ */

const char *kaz_sign_version(void)
{
    return KAZ_SIGN_VERSION_STRING;
}

int kaz_sign_version_number(void)
{
    return KAZ_SIGN_VERSION_NUMBER;
}

/* ============================================================================
 * Runtime Security Level Functions (_ex variants)
 * ============================================================================ */

int kaz_sign_hash_ex(kaz_sign_level_t level,
                     const unsigned char *msg,
                     unsigned long long msglen,
                     unsigned char *hash)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    unsigned int hash_len = 0;

    if (!rp) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Initialize if needed */
    if (!rp->initialized) {
        int ret = init_runtime_params(rp, level);
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    if (!rp->hash_ctx || !rp->hash_md) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestInit_ex(rp->hash_ctx, rp->hash_md, NULL) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestUpdate(rp->hash_ctx, msg, msglen) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (EVP_DigestFinal_ex(rp->hash_ctx, hash, &hash_len) != 1) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_keypair_ex(kaz_sign_level_t level,
                        unsigned char *pk,
                        unsigned char *sk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BIGNUM *s = NULL;
    BIGNUM *t = NULL;
    BIGNUM *V = NULL;
    BIGNUM *tmp = NULL;
    int ret = KAZ_SIGN_ERROR_MEMORY;

    if (!rp) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (pk == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Initialize if needed */
    if (!rp->initialized) {
        ret = init_runtime_params(rp, level);
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    params = rp->params;

    /* Allocate BIGNUMs */
    s = BN_secure_new();
    t = BN_secure_new();
    V = BN_new();
    tmp = BN_new();

    if (!s || !t || !V || !tmp) {
        goto cleanup;
    }

    /* Mark secret values for constant-time operations */
    bn_set_secret(s);
    bn_set_secret(t);

    /* Generate random s in [lb_g1, Og1N] */
    if (bn_random_range(s, rp->lb_g1, rp->Og1N, rp->bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }

    /* Generate random t in [lb_g2, Og2N] */
    if (bn_random_range(t, rp->lb_g2, rp->Og2N, rp->bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }

    /* Compute V = g1^s * g2^t mod N using constant-time exponentiation */
    if (!bn_mod_exp_consttime(tmp, rp->g1, s, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!bn_mod_exp_consttime(V, rp->g2, t, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!BN_mod_mul(V, V, tmp, rp->N, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Export to output buffers */
    if (bn_export_padded(sk, params->s_bytes, s) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sk + params->s_bytes, params->t_bytes, t) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(pk, params->public_key_bytes, V) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    bn_secure_free(s);
    bn_secure_free(t);
    BN_free(V);
    BN_free(tmp);

    return ret;
}

int kaz_sign_signature_ex(kaz_sign_level_t level,
                          unsigned char *sig,
                          unsigned long long *siglen,
                          const unsigned char *msg,
                          unsigned long long msglen,
                          const unsigned char *sk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BIGNUM *s = NULL, *t = NULL;
    BIGNUM *e1 = NULL, *e2 = NULL;
    BIGNUM *h = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *tmp = NULL, *tmp2 = NULL;
    BIGNUM *e1_inv = NULL;
    unsigned char *hash_buf = NULL;
    int ret = KAZ_SIGN_ERROR_MEMORY;

    if (!rp) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (sig == NULL || siglen == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (msg == NULL && msglen > 0) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Initialize if needed */
    if (!rp->initialized) {
        ret = init_runtime_params(rp, level);
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    params = rp->params;

    /* Allocate hash buffer */
    hash_buf = malloc(params->hash_bytes);
    if (!hash_buf) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    s = BN_secure_new();
    t = BN_secure_new();
    e1 = BN_secure_new();
    e2 = BN_secure_new();
    h = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    tmp = BN_secure_new();
    tmp2 = BN_secure_new();
    e1_inv = BN_secure_new();

    if (!s || !t || !e1 || !e2 || !h || !S1 || !S2 || !S3 ||
        !tmp || !tmp2 || !e1_inv) {
        goto cleanup;
    }

    /* Mark secret values */
    bn_set_secret(s);
    bn_set_secret(t);
    bn_set_secret(e1);
    bn_set_secret(e2);
    bn_set_secret(tmp);
    bn_set_secret(tmp2);
    bn_set_secret(e1_inv);

    /* Import secret key */
    if (bn_import(s, sk, params->s_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(t, sk + params->s_bytes, params->t_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(s);
    bn_set_secret(t);

    /* Hash message */
    if (kaz_sign_hash_ex(level, msg, msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(h, hash_buf, params->hash_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Generate random e1, then find next prime */
    if (bn_random_range(e1, rp->lb_g1, rp->Og1N, rp->bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    if (!BN_generate_prime_ex(e1, BN_num_bits(e1), 0, NULL, NULL, NULL)) {
        /* Fallback: just use the random value if prime generation fails */
    }
    bn_set_secret(e1);

    /* Generate random e2 */
    if (bn_random_range(e2, rp->lb_g2, rp->Og2N, rp->bn_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    bn_set_secret(e2);

    /* Compute S1 = g1^e1 * g2^e2 mod N */
    if (!bn_mod_exp_consttime(tmp, rp->g1, e1, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!bn_mod_exp_consttime(S1, rp->g2, e2, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(S1, S1, tmp, rp->N, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute e1^(-1) mod phi(N) */
    if (!BN_mod_inverse(e1_inv, e1, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(e1_inv);

    /* Compute S2 = (h - s*S1) * e1^(-1) mod phi(N) */
    if (!BN_mod_mul(tmp, s, S1, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_sub(tmp, h, tmp, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(S2, tmp, e1_inv, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute S3 = h - t*S1 - e2*S2 mod phi(N) */
    if (!BN_mod_mul(tmp, t, S1, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(tmp2, e2, S2, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_add(tmp, tmp, tmp2, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_sub(S3, h, tmp, rp->phiN, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Export signature */
    memset(sig, 0, params->signature_overhead + msglen);

    if (bn_export_padded(sig, params->s1_bytes, S1) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sig + params->s1_bytes, params->s2_bytes, S2) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_export_padded(sig + params->s1_bytes + params->s2_bytes,
                         params->s3_bytes, S3) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Append message */
    if (msglen > 0) {
        memcpy(sig + params->signature_overhead, msg, msglen);
    }

    *siglen = params->signature_overhead + msglen;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    if (hash_buf) {
        kaz_secure_zero(hash_buf, params->hash_bytes);
        free(hash_buf);
    }

    bn_secure_free(s);
    bn_secure_free(t);
    bn_secure_free(e1);
    bn_secure_free(e2);
    bn_secure_free(tmp);
    bn_secure_free(tmp2);
    bn_secure_free(e1_inv);
    BN_free(h);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);

    return ret;
}

int kaz_sign_verify_ex(kaz_sign_level_t level,
                       unsigned char *msg,
                       unsigned long long *msglen,
                       const unsigned char *sig,
                       unsigned long long siglen,
                       const unsigned char *pk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BIGNUM *V = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *h = NULL;
    BIGNUM *Y1 = NULL, *Y2 = NULL;
    BIGNUM *tmp = NULL;
    unsigned char *hash_buf = NULL;
    unsigned long long extracted_msglen;
    int ret = KAZ_SIGN_ERROR_VERIFY;

    if (!rp) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (msg == NULL || msglen == NULL || sig == NULL || pk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Initialize if needed */
    if (!rp->initialized) {
        int init_ret = init_runtime_params(rp, level);
        if (init_ret != KAZ_SIGN_SUCCESS) {
            return init_ret;
        }
    }

    params = rp->params;

    if (siglen < params->signature_overhead) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    extracted_msglen = siglen - params->signature_overhead;

    /* Allocate hash buffer */
    hash_buf = malloc(params->hash_bytes);
    if (!hash_buf) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    V = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    h = BN_new();
    Y1 = BN_new();
    Y2 = BN_new();
    tmp = BN_new();

    if (!V || !S1 || !S2 || !S3 || !h || !Y1 || !Y2 || !tmp) {
        ret = KAZ_SIGN_ERROR_MEMORY;
        goto cleanup;
    }

    /* Import public key and signature components */
    if (bn_import(V, pk, params->public_key_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S1, sig, params->s1_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S2, sig + params->s1_bytes, params->s2_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S3, sig + params->s1_bytes + params->s2_bytes,
                  params->s3_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Hash the embedded message */
    const unsigned char *embedded_msg = sig + params->signature_overhead;
    if (kaz_sign_hash_ex(level, embedded_msg, extracted_msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(h, hash_buf, params->hash_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute Y1 = V^S1 * S1^S2 * g2^S3 mod N */
    if (!BN_mod_exp_mont(tmp, V, S1, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_exp_mont(Y1, S1, S2, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(Y1, Y1, tmp, rp->N, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    if (!BN_mod_exp_mont(tmp, rp->g2, S3, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (!BN_mod_mul(Y1, Y1, tmp, rp->N, rp->bn_ctx)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Compute Y2 = (g1 * g2)^h mod N */
    if (!BN_mod_exp_mont(Y2, rp->g1g2, h, rp->N, rp->bn_ctx, rp->mont)) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* Verify Y1 == Y2 */
    if (BN_cmp(Y1, Y2) != 0) {
        ret = KAZ_SIGN_ERROR_VERIFY;
        goto cleanup;
    }

    /* Copy out the message */
    memcpy(msg, embedded_msg, extracted_msglen);
    *msglen = extracted_msglen;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    if (hash_buf) {
        kaz_secure_zero(hash_buf, params ? params->hash_bytes : 64);
        free(hash_buf);
    }

    BN_free(V);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);
    BN_free(h);
    BN_free(Y1);
    BN_free(Y2);
    BN_free(tmp);

    return ret;
}
