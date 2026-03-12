/*
 * KAZ-SIGN: Constant-Time Implementation using OpenSSL BIGNUM
 * Version 4.0 - Complete Algorithm Rewrite (3-component scheme)
 *
 * This implementation matches the Java kaz-pqc-core-v2.0 reference exactly.
 * Uses OpenSSL's BIGNUM library with constant-time operations.
 *
 * Key security features:
 * - BN_FLG_CONSTTIME flag on all secret values (s, t, e1, e2, e1_inv)
 * - BN_mod_exp_mont_consttime for all mod_exp with secret exponents
 * - Secure memory zeroization via kaz_secure_zero
 *
 * Algorithm: 3-component signature (S1, S2, S3) with simple verification.
 *
 * Key Generation:
 *   s = random in [2^(lOg1N-2), Og1N]
 *   t = random in [2^(lOg2N-2), Og2N]
 *   v = g1^s * g2^t mod N
 *   pk = v, sk = s || t
 *
 * Signing:
 *   h = BigInteger(1, SHA-256(msg) zero-padded to hash_bytes)
 *   e1 = nextProbablePrime(random in [2^(lOg1N-2), Og1N])
 *   e2 = random in [2^(lOg2N-2), Og2N]
 *   S1 = g2^e2 * g1^e1 mod N
 *   S2 = (h - s*S1) * e1^(-1) mod phiN
 *   S3 = h - t*S1 - e2*S2 mod phiN
 *
 * Verification:
 *   LHS = v^S1 * S1^S2 * g2^S3 mod N
 *   RHS = (g1*g2)^h mod N
 *   Accept iff LHS == RHS
 *
 * N is ODD, enabling full constant-time Montgomery support.
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
    .secret_key_bytes = 32,     /* s(16) + t(16) */
    .public_key_bytes = 54,     /* v(54) */
    .hash_bytes = 32,           /* SHA-256 */
    .signature_overhead = 162,  /* S1(54) + S2(54) + S3(54) */
    .v_bytes = 54,
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
    .secret_key_bytes = 50,     /* s(25) + t(25) */
    .public_key_bytes = 88,     /* v(88) */
    .hash_bytes = 48,           /* SHA-256 zero-padded to 48 */
    .signature_overhead = 264,  /* S1(88) + S2(88) + S3(88) */
    .v_bytes = 88,
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
    .secret_key_bytes = 64,     /* s(32) + t(32) */
    .public_key_bytes = 118,    /* v(118) */
    .hash_bytes = 64,           /* SHA-256 zero-padded to 64 */
    .signature_overhead = 354,  /* S1(118) + S2(118) + S3(118) */
    .v_bytes = 118,
    .s_bytes = 32,
    .t_bytes = 32,
    .s1_bytes = 118,
    .s2_bytes = 118,
    .s3_bytes = 118
};

/* ============================================================================
 * System Parameter String Constants (verbatim from Java SystemParameters.java)
 * ============================================================================ */

static const char *SP_g1 = "65537";
static const char *SP_g2 = "65539";

/* Per-level parameters (indexed 0=128, 1=192, 2=256) */
static const char *SP_N[3] = {
    "9680693320350411581735712527156160041331448806285781880953481207107506184928318589548473667621840334803765737814574120142199988285",
    "15982040643598444277320371265136974856402799594720686504760818091215333991414038871394426514903965899103553442859146701270930684879295849706045338879593833465052745734862675359470536861467492521046077102660572015",
    "29421818394147345935036136135391375994024126405325576672227398037493559452008116283594709069097880319117946343281357631447556041903884586208161678710597469727999746179863045388559147407457068275815914914983896392757878683919189075898269550939868181179868469970964809582599153788719655"
};

static const char *SP_phiN[3] = {
    "1862854061641389163337017925599133865006616816206541406153748908271169581801631840410608441366518309266967756800000000000000000000",
    "2852982385092065996343896318300390927321234264319221230294884622249277900787903710363361658485275185133309433619496986167576406960701801204725152385400156421631204526170043735085154304000000000000000000000000000",
    "50292424825163552562978587619437224014186391216845845274999569746745516008793250434217571033063294414288708058671634634590721488800764370309445841482820099012822307518112753015243262020075703403848545816307161422683474180459684923036013856370458624000000000000000000000000000000000"
};

static const char *SP_Og1N[3] = {
    "104096837085595768062256170741230052000",
    "12934000239870021828648909535012878456790556542848408504000",
    "49577346943749914278558040936897577826073730777121114343013903022328490384000"
};

static const char *SP_Og2N[3] = {
    "17349472847599294677042695123538342000",
    "12934000239870021828648909535012878456790556542848408504000",
    "24788673471874957139279020468448788913036865388560557171506951511164245192000"
};

/* ============================================================================
 * Runtime Parameter Cache (one per security level)
 * ============================================================================ */

typedef struct {
    /* System parameters as BIGNUMs */
    BIGNUM *N;
    BIGNUM *phiN;
    BIGNUM *g1;
    BIGNUM *g2;
    BIGNUM *Og1N;
    BIGNUM *Og2N;
    int lOg1N;          /* BN_num_bits(Og1N) */
    int lOg2N;          /* BN_num_bits(Og2N) */

    /* Level params reference */
    const kaz_sign_level_params_t *params;
    int initialized;
} kaz_runtime_params_t;

/* Runtime parameter caches for each level.
 * THREAD SAFETY: These globals are lazily initialized and NOT thread-safe.
 * Concurrent calls to kaz_sign_*_ex() for the same level may race on
 * initialization. Call kaz_sign_init_random() from a single thread before
 * concurrent use, or protect all kaz_sign_* calls with an external mutex.
 * Do NOT call kaz_sign_clear_level/clear_all while other threads are active. */
static kaz_runtime_params_t g_runtime_128 = { .initialized = 0 };
static kaz_runtime_params_t g_runtime_192 = { .initialized = 0 };
static kaz_runtime_params_t g_runtime_256 = { .initialized = 0 };

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

/* Export BIGNUM to fixed-size buffer (right-aligned, zero-padded, big-endian) */
static int bn_export_padded(unsigned char *buf, size_t buf_size, const BIGNUM *bn)
{
    memset(buf, 0, buf_size);

    if (bn == NULL || BN_is_zero(bn)) {
        return 0;
    }

    int bn_size = BN_num_bytes(bn);
    if ((size_t)bn_size > buf_size) {
        return -1;  /* Value too large for buffer */
    }

    /* BN_bn2binpad writes exactly buf_size bytes, zero-padded on the left */
    if (BN_bn2binpad(bn, buf, (int)buf_size) < 0) {
        return -1;
    }
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

/*
 * Sample a random BIGNUM uniformly in [lower, upper] via rejection sampling.
 * Matches Java getRandom.getRandomIntInRange().
 * Returns 0 on success, -1 on failure.
 */
static int sample_in_range(BIGNUM *result, const BIGNUM *lower, const BIGNUM *upper, BN_CTX *ctx)
{
    int ret = -1;
    BIGNUM *range, *r;

    BN_CTX_start(ctx);
    range = BN_CTX_get(ctx);
    r = BN_CTX_get(ctx);
    if (!range || !r) goto cleanup;

    /* range = upper - lower */
    if (!BN_sub(range, upper, lower)) goto cleanup;

    /* If range is negative or zero, just set result = lower */
    if (BN_is_negative(range) || BN_is_zero(range)) {
        if (!BN_copy(result, lower)) goto cleanup;
        ret = 0;
        goto cleanup;
    }

    /* Add 1 to make it inclusive: range = upper - lower + 1 */
    if (!BN_add_word(range, 1)) goto cleanup;

    /* Generate random in [0, range) */
    if (!BN_rand_range(r, range)) goto cleanup;

    /* result = r + lower */
    if (!BN_add(result, r, lower)) goto cleanup;

    ret = 0;

cleanup:
    BN_CTX_end(ctx);
    return ret;
}

/*
 * Find next probable prime >= start.
 * Matches Java's BigInteger.nextProbablePrime().
 * Uses BN_check_prime (OpenSSL 3.x).
 * Returns 0 on success, -1 on failure.
 */
static int bn_next_probable_prime(BIGNUM *result, const BIGNUM *start, BN_CTX *ctx)
{
    if (!BN_copy(result, start)) return -1;

    /* Java's nextProbablePrime returns strictly greater than start */
    if (!BN_add_word(result, 1)) return -1;

    /* Make odd if even */
    if (!BN_is_odd(result)) {
        if (!BN_add_word(result, 1)) return -1;
    }

    /* Search for prime */
    for (int attempts = 0; attempts < 10000; attempts++) {
        int is_prime = BN_check_prime(result, ctx, NULL);
        if (is_prime == 1) return 0;
        if (is_prime < 0) return -1;
        if (!BN_add_word(result, 2)) return -1;
    }
    return -1; /* Should not happen for reasonable inputs */
}

/* ============================================================================
 * Parameter Initialization
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

/* Convert level to array index (0,1,2) */
static int level_to_index(kaz_sign_level_t level)
{
    switch (level) {
        case KAZ_LEVEL_128: return 0;
        case KAZ_LEVEL_192: return 1;
        case KAZ_LEVEL_256: return 2;
        default: return -1;
    }
}

/* Initialize runtime parameters for a specific level */
static int init_runtime_params(kaz_runtime_params_t *rp, kaz_sign_level_t level)
{
    int ret = KAZ_SIGN_ERROR_MEMORY;
    int idx;

    if (rp->initialized) {
        return KAZ_SIGN_SUCCESS;
    }

    /* Get level parameters */
    rp->params = kaz_sign_get_level_params(level);
    if (!rp->params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    idx = level_to_index(level);
    if (idx < 0) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Allocate all BIGNUMs */
    rp->N = BN_new();
    rp->phiN = BN_new();
    rp->g1 = BN_new();
    rp->g2 = BN_new();
    rp->Og1N = BN_new();
    rp->Og2N = BN_new();

    if (!rp->N || !rp->phiN || !rp->g1 || !rp->g2 ||
        !rp->Og1N || !rp->Og2N) {
        goto cleanup;
    }

    /* Parse constants */
    if (!BN_dec2bn(&rp->g1, SP_g1)) goto cleanup;
    if (!BN_dec2bn(&rp->g2, SP_g2)) goto cleanup;

    /* Parse per-level constants */
    if (!BN_dec2bn(&rp->N, SP_N[idx])) goto cleanup;
    if (!BN_dec2bn(&rp->phiN, SP_phiN[idx])) goto cleanup;
    if (!BN_dec2bn(&rp->Og1N, SP_Og1N[idx])) goto cleanup;
    if (!BN_dec2bn(&rp->Og2N, SP_Og2N[idx])) goto cleanup;

    /* Derived: bit-lengths of orders */
    rp->lOg1N = BN_num_bits(rp->Og1N);
    rp->lOg2N = BN_num_bits(rp->Og2N);

    rp->initialized = 1;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    if (ret != KAZ_SIGN_SUCCESS) {
        BN_free(rp->N); rp->N = NULL;
        BN_clear_free(rp->phiN); rp->phiN = NULL;
        BN_free(rp->g1); rp->g1 = NULL;
        BN_free(rp->g2); rp->g2 = NULL;
        BN_free(rp->Og1N); rp->Og1N = NULL;
        BN_free(rp->Og2N); rp->Og2N = NULL;
        rp->initialized = 0;
    }

    return ret;
}

/* Clear runtime parameters for a specific level */
static void clear_runtime_params(kaz_runtime_params_t *rp)
{
    if (rp && rp->initialized) {
        BN_free(rp->N); rp->N = NULL;
        BN_clear_free(rp->phiN); rp->phiN = NULL;
        BN_free(rp->g1); rp->g1 = NULL;
        BN_free(rp->g2); rp->g2 = NULL;
        BN_free(rp->Og1N); rp->Og1N = NULL;
        BN_free(rp->Og2N); rp->Og2N = NULL;
        rp->params = NULL;
        rp->initialized = 0;
    }
}

/* ============================================================================
 * Public API: Level Management
 * ============================================================================ */

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

/* ============================================================================
 * Random Number Generation
 * ============================================================================ */

static int g_rand_initialized = 0;

/* Public API: Clear all security levels */
void kaz_sign_clear_all(void)
{
    clear_runtime_params(&g_runtime_128);
    clear_runtime_params(&g_runtime_192);
    clear_runtime_params(&g_runtime_256);
    g_rand_initialized = 0;
}

int kaz_sign_init_random(void)
{
    if (g_rand_initialized) {
        return KAZ_SIGN_SUCCESS;
    }

    /* Initialize the compile-time level */
    int ret = init_runtime_params(
        get_runtime_params((kaz_sign_level_t)KAZ_SECURITY_LEVEL),
        (kaz_sign_level_t)KAZ_SECURITY_LEVEL);
    if (ret != KAZ_SIGN_SUCCESS) {
        return ret;
    }

    g_rand_initialized = 1;
    return KAZ_SIGN_SUCCESS;
}

void kaz_sign_clear_random(void)
{
    kaz_sign_clear_all();
}

int kaz_sign_is_initialized(void)
{
    return g_rand_initialized;
}

/* ============================================================================
 * Hash Function
 *
 * Always SHA-256, zero-padded to hash_bytes (32/48/64).
 * ============================================================================ */

int kaz_sign_hash_ex(kaz_sign_level_t level,
                     const unsigned char *msg,
                     unsigned long long msglen,
                     unsigned char *hash)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    unsigned int hash_len = 0;
    unsigned char sha256_buf[32]; /* SHA-256 = 32 bytes */
    EVP_MD_CTX *hash_ctx = NULL;

    if (!rp || !params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (hash == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Initialize if needed */
    if (!rp->initialized) {
        int ret = init_runtime_params(rp, level);
        if (ret != KAZ_SIGN_SUCCESS) {
            return ret;
        }
    }

    /* Allocate per-call hash context for thread safety */
    hash_ctx = EVP_MD_CTX_new();
    if (!hash_ctx) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    if (msg == NULL && msglen > 0) {
        EVP_MD_CTX_free(hash_ctx);
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Always SHA-256 regardless of level */
    if (EVP_DigestInit_ex(hash_ctx, EVP_sha256(), NULL) != 1) {
        EVP_MD_CTX_free(hash_ctx);
        return KAZ_SIGN_ERROR_HASH;
    }

    if (msg != NULL && msglen > 0 && EVP_DigestUpdate(hash_ctx, msg, (size_t)msglen) != 1) {
        EVP_MD_CTX_free(hash_ctx);
        return KAZ_SIGN_ERROR_HASH;
    }

    if (EVP_DigestFinal_ex(hash_ctx, sha256_buf, &hash_len) != 1) {
        kaz_secure_zero(sha256_buf, sizeof(sha256_buf));
        EVP_MD_CTX_free(hash_ctx);
        return KAZ_SIGN_ERROR_HASH;
    }

    EVP_MD_CTX_free(hash_ctx);

    /* Zero-pad output: SHA-256 digest at front, trailing zeros (matches Java exactly:
     * System.arraycopy(digest, 0, buf, 0, len); new BigInteger(1, buf)) */
    memset(hash, 0, params->hash_bytes);
    memcpy(hash, sha256_buf, 32);
    kaz_secure_zero(sha256_buf, sizeof(sha256_buf));

    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_hash(const unsigned char *msg,
                  unsigned long long msglen,
                  unsigned char *hash)
{
    return kaz_sign_hash_ex((kaz_sign_level_t)KAZ_SECURITY_LEVEL, msg, msglen, hash);
}

/* ============================================================================
 * Key Generation (matches Java KAZSIGNKeyGenerator.java v2.0)
 *
 * s = random in [2^(lOg1N-2), Og1N]
 * t = random in [2^(lOg2N-2), Og2N]
 * v = g1^s * g2^t mod N
 * pk = v (v_bytes big-endian)
 * sk = s (s_bytes) || t (t_bytes) big-endian
 * ============================================================================ */

int kaz_sign_keypair_ex(kaz_sign_level_t level,
                        unsigned char *pk,
                        unsigned char *sk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BN_CTX *local_ctx = NULL;
    BIGNUM *s = NULL, *t = NULL;
    BIGNUM *lower_s = NULL, *lower_t = NULL;
    BIGNUM *g1_s = NULL, *g2_t = NULL, *v = NULL;
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

    /* Allocate per-call BN_CTX for thread safety */
    local_ctx = BN_CTX_new();
    if (!local_ctx) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    s = BN_secure_new();       /* secret */
    t = BN_secure_new();       /* secret */
    lower_s = BN_new();
    lower_t = BN_new();
    g1_s = BN_new();
    g2_t = BN_new();
    v = BN_new();

    if (!s || !t || !lower_s || !lower_t || !g1_s || !g2_t || !v) {
        goto cleanup;
    }

    bn_set_secret(s);
    bn_set_secret(t);

    /* lower_s = 2^(lOg1N - 2) */
    if (!BN_set_bit(lower_s, rp->lOg1N - 2)) goto cleanup;

    /* lower_t = 2^(lOg2N - 2) */
    if (!BN_set_bit(lower_t, rp->lOg2N - 2)) goto cleanup;

    /* s = random in [2^(lOg1N-2), Og1N] */
    if (sample_in_range(s, lower_s, rp->Og1N, local_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    bn_set_secret(s);

    /* t = random in [2^(lOg2N-2), Og2N] */
    if (sample_in_range(t, lower_t, rp->Og2N, local_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    bn_set_secret(t);

    /* g1_s = g1^s mod N (N is odd, constant-time Montgomery) */
    if (!BN_mod_exp_mont_consttime(g1_s, rp->g1, s, rp->N, local_ctx, NULL)) goto cleanup;

    /* g2_t = g2^t mod N */
    if (!BN_mod_exp_mont_consttime(g2_t, rp->g2, t, rp->N, local_ctx, NULL)) goto cleanup;

    /* v = g1_s * g2_t mod N */
    if (!BN_mod_mul(v, g1_s, g2_t, rp->N, local_ctx)) goto cleanup;

    /* pk = v (v_bytes big-endian) */
    if (bn_export_padded(pk, params->v_bytes, v) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }

    /* sk = s (s_bytes) || t (t_bytes) big-endian */
    if (bn_export_padded(sk, params->s_bytes, s) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }
    if (bn_export_padded(sk + params->s_bytes, params->t_bytes, t) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    BN_CTX_free(local_ctx);
    bn_secure_free(s);
    bn_secure_free(t);
    BN_free(lower_s);
    BN_free(lower_t);
    BN_free(g1_s);
    BN_free(g2_t);
    BN_free(v);

    return ret;
}

int kaz_sign_keypair(unsigned char *pk, unsigned char *sk)
{
    if (!g_rand_initialized) {
        int ret = kaz_sign_init_random();
        if (ret != KAZ_SIGN_SUCCESS) return ret;
    }
    return kaz_sign_keypair_ex((kaz_sign_level_t)KAZ_SECURITY_LEVEL, pk, sk);
}

/* ============================================================================
 * Signature Generation (matches Java KAZSIGNSigner.java v2.0)
 *
 * h = BigInteger(1, SHA-256(msg) zero-padded to hash_bytes)
 * e1 = nextProbablePrime(random in [2^(lOg1N-2), Og1N])
 * e2 = random in [2^(lOg2N-2), Og2N]
 * S1 = g2^e2 * g1^e1 mod N
 * S2 = (h - s*S1) * e1^(-1) mod phiN
 * S3 = h - t*S1 - e2*S2 mod phiN
 * Output: S1 || S2 || S3 || message
 * ============================================================================ */

int kaz_sign_signature_ex(kaz_sign_level_t level,
                          unsigned char *sig,
                          unsigned long long *siglen,
                          const unsigned char *msg,
                          unsigned long long msglen,
                          const unsigned char *sk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BN_CTX *local_ctx = NULL;
    BIGNUM *s_bn = NULL, *t_bn = NULL;
    BIGNUM *hashInt = NULL;
    BIGNUM *lower_e1 = NULL, *lower_e2 = NULL;
    BIGNUM *e1 = NULL, *e2 = NULL, *e1_inv = NULL;
    BIGNUM *g1_e1 = NULL, *g2_e2 = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *tmp = NULL, *tmp2 = NULL;
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

    /* Allocate per-call BN_CTX */
    local_ctx = BN_CTX_new();
    if (!local_ctx) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate hash buffer */
    hash_buf = malloc(params->hash_bytes);
    if (!hash_buf) {
        BN_CTX_free(local_ctx);
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    s_bn = BN_secure_new();    /* secret */
    t_bn = BN_secure_new();    /* secret */
    hashInt = BN_new();
    lower_e1 = BN_new();
    lower_e2 = BN_new();
    e1 = BN_secure_new();      /* secret */
    e2 = BN_secure_new();      /* secret */
    e1_inv = BN_secure_new();  /* secret */
    g1_e1 = BN_new();
    g2_e2 = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    tmp = BN_new();
    tmp2 = BN_new();

    if (!s_bn || !t_bn || !hashInt || !lower_e1 || !lower_e2 ||
        !e1 || !e2 || !e1_inv || !g1_e1 || !g2_e2 ||
        !S1 || !S2 || !S3 || !tmp || !tmp2) {
        goto cleanup;
    }

    bn_set_secret(s_bn);
    bn_set_secret(t_bn);
    bn_set_secret(e1);
    bn_set_secret(e2);
    bn_set_secret(e1_inv);

    /* Import secret key: sk = s (s_bytes) || t (t_bytes) */
    if (bn_import(s_bn, sk, params->s_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(s_bn);

    if (bn_import(t_bn, sk + params->s_bytes, params->t_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    bn_set_secret(t_bn);

    /* Hash the message: h = BigInteger(1, SHA-256(msg) zero-padded to hash_bytes) */
    if (kaz_sign_hash_ex(level, msg, msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
        ret = KAZ_SIGN_ERROR_HASH;
        goto cleanup;
    }
    if (bn_import(hashInt, hash_buf, params->hash_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* lower_e1 = 2^(lOg1N - 2) */
    if (!BN_set_bit(lower_e1, rp->lOg1N - 2)) goto cleanup;

    /* lower_e2 = 2^(lOg2N - 2) */
    if (!BN_set_bit(lower_e2, rp->lOg2N - 2)) goto cleanup;

    /* e1 = random in [2^(lOg1N-2), Og1N], then find next probable prime > e1.
     * Retry if e1_inv doesn't exist (extremely unlikely since e1 is prime). */
    {
        int inv_ok = 0;
        for (int retry = 0; retry < 20 && !inv_ok; retry++) {
            if (sample_in_range(e1, lower_e1, rp->Og1N, local_ctx) != 0) {
                ret = KAZ_SIGN_ERROR_RNG;
                goto cleanup;
            }
            if (bn_next_probable_prime(e1, e1, local_ctx) != 0) {
                ret = KAZ_SIGN_ERROR_RNG;
                goto cleanup;
            }
            bn_set_secret(e1);

            /* e1_inv = e1^(-1) mod phiN */
            /* Verify e1 is still in a reasonable range after prime search */
            if (BN_cmp(e1, rp->Og1N) > 0) {
                continue; /* e1 exceeded Og1N, retry with new sample */
            }

            if (BN_mod_inverse(e1_inv, e1, rp->phiN, local_ctx)) {
                inv_ok = 1;
            } else {
                ERR_clear_error();
            }
        }
        if (!inv_ok) {
            ret = KAZ_SIGN_ERROR_INVALID;
            goto cleanup;
        }
        bn_set_secret(e1_inv);
    }

    /* e2 = random in [2^(lOg2N-2), Og2N] */
    if (sample_in_range(e2, lower_e2, rp->Og2N, local_ctx) != 0) {
        ret = KAZ_SIGN_ERROR_RNG;
        goto cleanup;
    }
    bn_set_secret(e2);

    /* S1 = g2^e2 * g1^e1 mod N (N is odd, constant-time Montgomery) */
    if (!BN_mod_exp_mont_consttime(g2_e2, rp->g2, e2, rp->N, local_ctx, NULL)) goto cleanup;
    if (!BN_mod_exp_mont_consttime(g1_e1, rp->g1, e1, rp->N, local_ctx, NULL)) goto cleanup;
    if (!BN_mod_mul(S1, g2_e2, g1_e1, rp->N, local_ctx)) goto cleanup;

    /* S2 = (h - s*S1) * e1^(-1) mod phiN */
    /* tmp = s * S1 mod phiN */
    if (!BN_mod_mul(tmp, s_bn, S1, rp->phiN, local_ctx)) goto cleanup;
    /* tmp2 = h - s*S1 mod phiN */
    if (!BN_mod_sub(tmp2, hashInt, tmp, rp->phiN, local_ctx)) goto cleanup;
    /* S2 = tmp2 * e1_inv mod phiN */
    if (!BN_mod_mul(S2, tmp2, e1_inv, rp->phiN, local_ctx)) goto cleanup;

    /* S3 = h - t*S1 - e2*S2 mod phiN */
    /* tmp = t * S1 mod phiN */
    if (!BN_mod_mul(tmp, t_bn, S1, rp->phiN, local_ctx)) goto cleanup;
    /* tmp2 = e2 * S2 mod phiN */
    if (!BN_mod_mul(tmp2, e2, S2, rp->phiN, local_ctx)) goto cleanup;
    /* S3 = h - tmp - tmp2 mod phiN */
    if (!BN_mod_sub(S3, hashInt, tmp, rp->phiN, local_ctx)) goto cleanup;
    if (!BN_mod_sub(S3, S3, tmp2, rp->phiN, local_ctx)) goto cleanup;

    /* Output: S1(s1_bytes) || S2(s2_bytes) || S3(s3_bytes) || message */
    if (bn_export_padded(sig, params->s1_bytes, S1) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }
    if (bn_export_padded(sig + params->s1_bytes, params->s2_bytes, S2) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }
    if (bn_export_padded(sig + params->s1_bytes + params->s2_bytes,
                         params->s3_bytes, S3) != 0) {
        ret = KAZ_SIGN_ERROR_BUFFER;
        goto cleanup;
    }

    /* Copy message after signature components */
    if (msg != NULL && msglen > 0) {
        memcpy(sig + params->signature_overhead, msg, (size_t)msglen);
    }
    *siglen = params->signature_overhead + msglen;

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    BN_CTX_free(local_ctx);
    if (hash_buf) {
        kaz_secure_zero(hash_buf, params ? params->hash_bytes : 64);
        free(hash_buf);
    }

    bn_secure_free(s_bn);
    bn_secure_free(t_bn);
    BN_free(hashInt);
    BN_free(lower_e1);
    BN_free(lower_e2);
    bn_secure_free(e1);
    bn_secure_free(e2);
    bn_secure_free(e1_inv);
    BN_free(g1_e1);
    BN_free(g2_e2);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);
    BN_free(tmp);
    BN_free(tmp2);

    return ret;
}

int kaz_sign_signature(unsigned char *sig,
                       unsigned long long *siglen,
                       const unsigned char *msg,
                       unsigned long long msglen,
                       const unsigned char *sk)
{
    if (!g_rand_initialized) {
        int ret = kaz_sign_init_random();
        if (ret != KAZ_SIGN_SUCCESS) return ret;
    }
    return kaz_sign_signature_ex((kaz_sign_level_t)KAZ_SECURITY_LEVEL,
                                 sig, siglen, msg, msglen, sk);
}

/* ============================================================================
 * Signature Verification (matches Java KAZSIGNVerifier.java v2.0)
 *
 * h = BigInteger(1, SHA-256(msg) zero-padded to hash_bytes)
 * V = v mod N
 * S1' = S1 mod N
 * LHS = V^S1' * S1'^S2 * g2^S3 mod N
 * RHS = (g1*g2)^h mod N
 * Accept iff LHS == RHS
 * Extract message from sig[signature_overhead:]
 * ============================================================================ */

int kaz_sign_verify_ex(kaz_sign_level_t level,
                       unsigned char *msg,
                       unsigned long long *msglen,
                       const unsigned char *sig,
                       unsigned long long siglen,
                       const unsigned char *pk)
{
    kaz_runtime_params_t *rp = get_runtime_params(level);
    const kaz_sign_level_params_t *params;
    BN_CTX *local_ctx = NULL;
    BIGNUM *V = NULL;
    BIGNUM *S1 = NULL, *S2 = NULL, *S3 = NULL;
    BIGNUM *hashInt = NULL;
    BIGNUM *V_S1 = NULL, *S1_S2 = NULL, *g2_S3 = NULL;
    BIGNUM *g1g2 = NULL;
    BIGNUM *LHS = NULL, *RHS = NULL;
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

    /* Allocate per-call BN_CTX */
    local_ctx = BN_CTX_new();
    if (!local_ctx) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate hash buffer */
    hash_buf = malloc(params->hash_bytes);
    if (!hash_buf) {
        BN_CTX_free(local_ctx);
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Allocate BIGNUMs */
    V = BN_new();
    S1 = BN_new();
    S2 = BN_new();
    S3 = BN_new();
    hashInt = BN_new();
    V_S1 = BN_new();
    S1_S2 = BN_new();
    g2_S3 = BN_new();
    g1g2 = BN_new();
    LHS = BN_new();
    RHS = BN_new();

    if (!V || !S1 || !S2 || !S3 || !hashInt ||
        !V_S1 || !S1_S2 || !g2_S3 || !g1g2 ||
        !LHS || !RHS) {
        ret = KAZ_SIGN_ERROR_MEMORY;
        goto cleanup;
    }

    /* Parse pk = v (v_bytes) */
    if (bn_import(V, pk, params->v_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* V = v mod N */
    if (!BN_mod(V, V, rp->N, local_ctx)) goto cleanup;

    /* Parse sig = S1(s1_bytes) || S2(s2_bytes) || S3(s3_bytes) || [message] */
    if (bn_import(S1, sig, params->s1_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S2, sig + params->s1_bytes, params->s2_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }
    if (bn_import(S3, sig + params->s1_bytes + params->s2_bytes, params->s3_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* S1' = S1 mod N */
    if (!BN_mod(S1, S1, rp->N, local_ctx)) goto cleanup;

    /* Hash the embedded message */
    {
        const unsigned char *embedded_msg = sig + params->signature_overhead;
        if (kaz_sign_hash_ex(level, embedded_msg, extracted_msglen, hash_buf) != KAZ_SIGN_SUCCESS) {
            ret = KAZ_SIGN_ERROR_INVALID;
            goto cleanup;
        }
    }
    if (bn_import(hashInt, hash_buf, params->hash_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_INVALID;
        goto cleanup;
    }

    /* LHS = V^S1' * S1'^S2 * g2^S3 mod N */
    /* V^S1 mod N (public values, use regular mod_exp — N is odd) */
    if (!BN_mod_exp(V_S1, V, S1, rp->N, local_ctx)) goto cleanup;

    /* S1^S2 mod N */
    if (!BN_mod_exp(S1_S2, S1, S2, rp->N, local_ctx)) goto cleanup;

    /* g2^S3 mod N */
    if (!BN_mod_exp(g2_S3, rp->g2, S3, rp->N, local_ctx)) goto cleanup;

    /* LHS = V_S1 * S1_S2 * g2_S3 mod N */
    if (!BN_mod_mul(LHS, V_S1, S1_S2, rp->N, local_ctx)) goto cleanup;
    if (!BN_mod_mul(LHS, LHS, g2_S3, rp->N, local_ctx)) goto cleanup;

    /* RHS = (g1*g2)^h mod N */
    if (!BN_mod_mul(g1g2, rp->g1, rp->g2, rp->N, local_ctx)) goto cleanup;
    if (!BN_mod_exp(RHS, g1g2, hashInt, rp->N, local_ctx)) goto cleanup;

    /* Accept iff LHS == RHS */
    if (BN_cmp(LHS, RHS) != 0) {
        ret = KAZ_SIGN_ERROR_VERIFY;
        goto cleanup;
    }

    /* All checks passed - copy out the message */
    {
        const unsigned char *embedded_msg = sig + params->signature_overhead;
        memcpy(msg, embedded_msg, (size_t)extracted_msglen);
    }
    *msglen = extracted_msglen;
    ret = KAZ_SIGN_SUCCESS;

cleanup:
    BN_CTX_free(local_ctx);
    if (hash_buf) {
        kaz_secure_zero(hash_buf, params ? params->hash_bytes : 64);
        free(hash_buf);
    }

    BN_free(V);
    BN_free(S1);
    BN_free(S2);
    BN_free(S3);
    BN_free(hashInt);
    BN_free(V_S1);
    BN_free(S1_S2);
    BN_free(g2_S3);
    BN_free(g1g2);
    BN_free(LHS);
    BN_free(RHS);

    return ret;
}

int kaz_sign_verify(unsigned char *msg,
                    unsigned long long *msglen,
                    const unsigned char *sig,
                    unsigned long long siglen,
                    const unsigned char *pk)
{
    if (!g_rand_initialized) {
        int ret = kaz_sign_init_random();
        if (ret != KAZ_SIGN_SUCCESS) return ret;
    }
    return kaz_sign_verify_ex((kaz_sign_level_t)KAZ_SECURITY_LEVEL,
                               msg, msglen, sig, siglen, pk);
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
 * KazWire Encoding/Decoding
 * ============================================================================ */

static int level_to_wire_alg(kaz_sign_level_t level) {
    switch (level) {
        case KAZ_LEVEL_128: return KAZ_WIRE_SIGN_128;
        case KAZ_LEVEL_192: return KAZ_WIRE_SIGN_192;
        case KAZ_LEVEL_256: return KAZ_WIRE_SIGN_256;
        default: return -1;
    }
}

static int wire_alg_to_level(int alg) {
    switch (alg) {
        case KAZ_WIRE_SIGN_128: return KAZ_LEVEL_128;
        case KAZ_WIRE_SIGN_192: return KAZ_LEVEL_192;
        case KAZ_WIRE_SIGN_256: return KAZ_LEVEL_256;
        default: return 0; /* 0 is not a valid level */
    }
}

static void wire_write_header(unsigned char *out, int alg_id, int type_id) {
    out[0] = KAZ_WIRE_MAGIC_HI;
    out[1] = KAZ_WIRE_MAGIC_LO;
    out[2] = (unsigned char)alg_id;
    out[3] = (unsigned char)type_id;
    out[4] = KAZ_WIRE_VERSION;
}

static int wire_validate_header(const unsigned char *wire, size_t wire_len,
                                int expected_type, kaz_sign_level_t *level) {
    if (wire_len < KAZ_WIRE_HEADER_LEN)
        return KAZ_SIGN_ERROR_INVALID;
    if (wire[0] != KAZ_WIRE_MAGIC_HI || wire[1] != KAZ_WIRE_MAGIC_LO)
        return KAZ_SIGN_ERROR_INVALID;
    if (wire[3] != (unsigned char)expected_type)
        return KAZ_SIGN_ERROR_INVALID;
    if (wire[4] != KAZ_WIRE_VERSION)
        return KAZ_SIGN_ERROR_INVALID;

    int lvl_int = wire_alg_to_level(wire[2]);
    if (lvl_int == 0)
        return KAZ_SIGN_ERROR_INVALID;
    kaz_sign_level_t lvl = (kaz_sign_level_t)lvl_int;

    *level = lvl;
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_pubkey_to_wire(kaz_sign_level_t level,
                            const unsigned char *pk, size_t pk_len,
                            unsigned char *out, size_t *out_len) {
    if (!pk || !out_len)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    if (pk_len != params->public_key_bytes)
        return KAZ_SIGN_ERROR_INVALID;

    size_t needed = KAZ_WIRE_HEADER_LEN + params->public_key_bytes;

    if (!out) {
        *out_len = needed;
        return KAZ_SIGN_SUCCESS;
    }

    if (*out_len < needed)
        return KAZ_SIGN_ERROR_BUFFER;

    int alg = level_to_wire_alg(level);
    if (alg < 0)
        return KAZ_SIGN_ERROR_INVALID;

    wire_write_header(out, alg, KAZ_WIRE_TYPE_PUB);
    memcpy(out + KAZ_WIRE_HEADER_LEN, pk, params->public_key_bytes);
    *out_len = needed;
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_pubkey_from_wire(const unsigned char *wire, size_t wire_len,
                              kaz_sign_level_t *level,
                              unsigned char *pk, size_t *pk_len) {
    if (!wire || !level || !pk || !pk_len)
        return KAZ_SIGN_ERROR_INVALID;

    kaz_sign_level_t lvl;
    int ret = wire_validate_header(wire, wire_len, KAZ_WIRE_TYPE_PUB, &lvl);
    if (ret != KAZ_SIGN_SUCCESS)
        return ret;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(lvl);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    size_t expected = KAZ_WIRE_HEADER_LEN + params->public_key_bytes;
    if (wire_len != expected)
        return KAZ_SIGN_ERROR_INVALID;

    if (*pk_len < params->public_key_bytes)
        return KAZ_SIGN_ERROR_BUFFER;

    *level = lvl;
    *pk_len = params->public_key_bytes;
    memcpy(pk, wire + KAZ_WIRE_HEADER_LEN, params->public_key_bytes);
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_privkey_to_wire(kaz_sign_level_t level,
                             const unsigned char *sk, size_t sk_len,
                             unsigned char *out, size_t *out_len) {
    if (!sk || !out_len)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    if (sk_len != params->secret_key_bytes)
        return KAZ_SIGN_ERROR_INVALID;

    size_t needed = KAZ_WIRE_HEADER_LEN + params->secret_key_bytes;

    if (!out) {
        *out_len = needed;
        return KAZ_SIGN_SUCCESS;
    }

    if (*out_len < needed)
        return KAZ_SIGN_ERROR_BUFFER;

    int alg = level_to_wire_alg(level);
    if (alg < 0)
        return KAZ_SIGN_ERROR_INVALID;

    wire_write_header(out, alg, KAZ_WIRE_TYPE_PRIV);
    memcpy(out + KAZ_WIRE_HEADER_LEN, sk, params->secret_key_bytes);
    *out_len = needed;
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_privkey_from_wire(const unsigned char *wire, size_t wire_len,
                               kaz_sign_level_t *level,
                               unsigned char *sk, size_t *sk_len) {
    if (!wire || !level || !sk || !sk_len)
        return KAZ_SIGN_ERROR_INVALID;

    kaz_sign_level_t lvl;
    int ret = wire_validate_header(wire, wire_len, KAZ_WIRE_TYPE_PRIV, &lvl);
    if (ret != KAZ_SIGN_SUCCESS)
        return ret;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(lvl);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    size_t expected = KAZ_WIRE_HEADER_LEN + params->secret_key_bytes;
    if (wire_len != expected)
        return KAZ_SIGN_ERROR_INVALID;

    if (*sk_len < params->secret_key_bytes)
        return KAZ_SIGN_ERROR_BUFFER;

    *level = lvl;
    *sk_len = params->secret_key_bytes;
    memcpy(sk, wire + KAZ_WIRE_HEADER_LEN, params->secret_key_bytes);
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_sig_to_wire(kaz_sign_level_t level,
                         const unsigned char *sig, size_t sig_len,
                         unsigned char *out, size_t *out_len) {
    if (!sig || !out_len)
        return KAZ_SIGN_ERROR_INVALID;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    if (sig_len != params->signature_overhead)
        return KAZ_SIGN_ERROR_INVALID;

    size_t needed = KAZ_WIRE_HEADER_LEN + params->signature_overhead;

    if (!out) {
        *out_len = needed;
        return KAZ_SIGN_SUCCESS;
    }

    if (*out_len < needed)
        return KAZ_SIGN_ERROR_BUFFER;

    int alg = level_to_wire_alg(level);
    if (alg < 0)
        return KAZ_SIGN_ERROR_INVALID;

    wire_write_header(out, alg, KAZ_WIRE_TYPE_SIG_DET);
    memcpy(out + KAZ_WIRE_HEADER_LEN, sig, params->signature_overhead);
    *out_len = needed;
    return KAZ_SIGN_SUCCESS;
}

int kaz_sign_sig_from_wire(const unsigned char *wire, size_t wire_len,
                           kaz_sign_level_t *level,
                           unsigned char *sig, size_t *sig_len) {
    if (!wire || !level || !sig || !sig_len)
        return KAZ_SIGN_ERROR_INVALID;

    kaz_sign_level_t lvl;
    int ret = wire_validate_header(wire, wire_len, KAZ_WIRE_TYPE_SIG_DET, &lvl);
    if (ret != KAZ_SIGN_SUCCESS)
        return ret;

    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(lvl);
    if (!params)
        return KAZ_SIGN_ERROR_INVALID;

    size_t expected = KAZ_WIRE_HEADER_LEN + params->signature_overhead;
    if (wire_len != expected)
        return KAZ_SIGN_ERROR_INVALID;

    if (*sig_len < params->signature_overhead)
        return KAZ_SIGN_ERROR_BUFFER;

    *level = lvl;
    *sig_len = params->signature_overhead;
    memcpy(sig, wire + KAZ_WIRE_HEADER_LEN, params->signature_overhead);
    return KAZ_SIGN_SUCCESS;
}
