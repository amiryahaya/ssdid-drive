/*
 * KAZ-SIGN Key Derivation Function (KDF) Implementation
 *
 * Implements HKDF (HMAC-based Key Derivation Function) per RFC 5869
 * using OpenSSL's EVP interface.
 */

#include "kaz/kdf.h"
#include "kaz/security.h"
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/kdf.h>
#include <string.h>

/* Use SHA-512 as the default hash for KDF */
#define KDF_HASH_ALG EVP_sha512()
#define KDF_HASH_LEN 64

/* ============================================================================
 * HKDF-Extract Implementation
 * ============================================================================ */

int kaz_hkdf_extract(const unsigned char *salt, size_t salt_len,
                     const unsigned char *ikm, size_t ikm_len,
                     unsigned char *prk, size_t *prk_len)
{
    unsigned char default_salt[KDF_HASH_LEN];
    const unsigned char *actual_salt;
    size_t actual_salt_len;
    unsigned int out_len;

    /* Validate inputs */
    if (ikm == NULL || prk == NULL || prk_len == NULL) {
        return KAZ_KDF_ERROR_NULL_PTR;
    }

    if (ikm_len == 0) {
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    /* Use zero salt if none provided (per RFC 5869) */
    if (salt == NULL || salt_len == 0) {
        memset(default_salt, 0, KDF_HASH_LEN);
        actual_salt = default_salt;
        actual_salt_len = KDF_HASH_LEN;
    } else {
        actual_salt = salt;
        actual_salt_len = salt_len;
    }

    /* PRK = HMAC-Hash(salt, IKM) */
    if (HMAC(KDF_HASH_ALG, actual_salt, (int)actual_salt_len,
             ikm, ikm_len, prk, &out_len) == NULL) {
        return KAZ_KDF_ERROR_CRYPTO;
    }

    *prk_len = out_len;

    /* Clear default salt if used */
    if (salt == NULL || salt_len == 0) {
        kaz_secure_zero(default_salt, KDF_HASH_LEN);
    }

    return KAZ_KDF_SUCCESS;
}

/* ============================================================================
 * HKDF-Expand Implementation
 * ============================================================================ */

int kaz_hkdf_expand(const unsigned char *prk, size_t prk_len,
                    const unsigned char *info, size_t info_len,
                    unsigned char *okm, size_t okm_len)
{
    unsigned char T[KDF_HASH_LEN];
    unsigned char block[KDF_HASH_LEN + 256 + 1]; /* T || info || counter */
    size_t T_len = 0;
    size_t done = 0;
    unsigned char counter = 1;
    unsigned int out_len;
    int ret = KAZ_KDF_SUCCESS;

    /* Validate inputs */
    if (prk == NULL || okm == NULL) {
        return KAZ_KDF_ERROR_NULL_PTR;
    }

    if (prk_len < KDF_HASH_LEN) {
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    if (okm_len > KAZ_KDF_MAX_OUTPUT_LEN) {
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    if (okm_len == 0) {
        return KAZ_KDF_SUCCESS;
    }

    /* Generate output in blocks */
    while (done < okm_len) {
        size_t block_len = 0;

        /* T(i) = HMAC-Hash(PRK, T(i-1) || info || counter) */
        if (T_len > 0) {
            memcpy(block, T, T_len);
            block_len = T_len;
        }

        if (info != NULL && info_len > 0) {
            memcpy(block + block_len, info, info_len);
            block_len += info_len;
        }

        block[block_len++] = counter;

        if (HMAC(KDF_HASH_ALG, prk, (int)prk_len,
                 block, block_len, T, &out_len) == NULL) {
            ret = KAZ_KDF_ERROR_CRYPTO;
            goto cleanup;
        }

        T_len = out_len;

        /* Copy output */
        size_t copy_len = okm_len - done;
        if (copy_len > T_len) {
            copy_len = T_len;
        }
        memcpy(okm + done, T, copy_len);
        done += copy_len;
        counter++;

        if (counter == 0) {
            /* Counter overflow - too much output requested */
            ret = KAZ_KDF_ERROR_INVALID_LEN;
            goto cleanup;
        }
    }

cleanup:
    kaz_secure_zero(T, sizeof(T));
    kaz_secure_zero(block, sizeof(block));

    return ret;
}

/* ============================================================================
 * Combined HKDF (Extract-and-Expand)
 * ============================================================================ */

int kaz_hkdf(const unsigned char *salt, size_t salt_len,
             const unsigned char *ikm, size_t ikm_len,
             const unsigned char *info, size_t info_len,
             unsigned char *okm, size_t okm_len)
{
    unsigned char prk[KDF_HASH_LEN];
    size_t prk_len;
    int ret;

    /* Extract */
    ret = kaz_hkdf_extract(salt, salt_len, ikm, ikm_len, prk, &prk_len);
    if (ret != KAZ_KDF_SUCCESS) {
        return ret;
    }

    /* Expand */
    ret = kaz_hkdf_expand(prk, prk_len, info, info_len, okm, okm_len);

    /* Clear PRK */
    kaz_secure_zero(prk, sizeof(prk));

    return ret;
}

/* ============================================================================
 * KAZ-SIGN Specific Key Derivation
 * ============================================================================ */

int kaz_kdf_derive_secret_key(const unsigned char *seed, size_t seed_len,
                              unsigned char *s_bytes, size_t s_len,
                              unsigned char *t_bytes, size_t t_len)
{
    unsigned char prk[KDF_HASH_LEN];
    size_t prk_len;
    int ret;

    /* Validate inputs */
    if (seed == NULL || s_bytes == NULL || t_bytes == NULL) {
        return KAZ_KDF_ERROR_NULL_PTR;
    }

    if (seed_len < 32) { /* Minimum 256 bits of entropy */
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    /* Extract PRK from seed using SK label as salt */
    ret = kaz_hkdf_extract(
        (const unsigned char *)KAZ_KDF_LABEL_SECRET_KEY,
        strlen(KAZ_KDF_LABEL_SECRET_KEY),
        seed, seed_len, prk, &prk_len);

    if (ret != KAZ_KDF_SUCCESS) {
        goto cleanup;
    }

    /* Derive s component */
    ret = kaz_hkdf_expand(prk, prk_len,
                          (const unsigned char *)"s", 1,
                          s_bytes, s_len);
    if (ret != KAZ_KDF_SUCCESS) {
        goto cleanup;
    }

    /* Derive t component */
    ret = kaz_hkdf_expand(prk, prk_len,
                          (const unsigned char *)"t", 1,
                          t_bytes, t_len);

cleanup:
    kaz_secure_zero(prk, sizeof(prk));

    return ret;
}

int kaz_kdf_derive_signing_randomness(const unsigned char *seed, size_t seed_len,
                                      const unsigned char *sk, size_t sk_len,
                                      const unsigned char *msg, size_t msg_len,
                                      uint32_t counter,
                                      unsigned char *output, size_t out_len)
{
    unsigned char combined_ikm[512]; /* seed || sk */
    size_t combined_len;
    unsigned char info[256];         /* msg hash || counter */
    size_t info_len;
    unsigned char msg_hash[KDF_HASH_LEN];
    unsigned int hash_len;
    int ret;

    /* Validate inputs */
    if (seed == NULL || sk == NULL || output == NULL) {
        return KAZ_KDF_ERROR_NULL_PTR;
    }

    if (seed_len + sk_len > sizeof(combined_ikm)) {
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    /* Combine seed and secret key as IKM */
    memcpy(combined_ikm, seed, seed_len);
    memcpy(combined_ikm + seed_len, sk, sk_len);
    combined_len = seed_len + sk_len;

    /* Hash the message to limit info size */
    if (msg != NULL && msg_len > 0) {
        EVP_MD_CTX *ctx = EVP_MD_CTX_new();
        if (ctx == NULL) {
            ret = KAZ_KDF_ERROR_CRYPTO;
            goto cleanup;
        }

        if (EVP_DigestInit_ex(ctx, KDF_HASH_ALG, NULL) != 1 ||
            EVP_DigestUpdate(ctx, msg, msg_len) != 1 ||
            EVP_DigestFinal_ex(ctx, msg_hash, &hash_len) != 1) {
            EVP_MD_CTX_free(ctx);
            ret = KAZ_KDF_ERROR_CRYPTO;
            goto cleanup;
        }
        EVP_MD_CTX_free(ctx);
    } else {
        memset(msg_hash, 0, KDF_HASH_LEN);
        hash_len = KDF_HASH_LEN;
    }

    /* Build info: msg_hash || counter */
    memcpy(info, msg_hash, hash_len);
    info[hash_len] = (unsigned char)(counter >> 24);
    info[hash_len + 1] = (unsigned char)(counter >> 16);
    info[hash_len + 2] = (unsigned char)(counter >> 8);
    info[hash_len + 3] = (unsigned char)(counter);
    info_len = hash_len + 4;

    /* Derive randomness */
    ret = kaz_hkdf(
        (const unsigned char *)KAZ_KDF_LABEL_RANDOM,
        strlen(KAZ_KDF_LABEL_RANDOM),
        combined_ikm, combined_len,
        info, info_len,
        output, out_len);

cleanup:
    kaz_secure_zero(combined_ikm, sizeof(combined_ikm));
    kaz_secure_zero(msg_hash, sizeof(msg_hash));
    kaz_secure_zero(info, sizeof(info));

    return ret;
}

int kaz_kdf_expand_seed(const unsigned char *seed, size_t seed_len,
                        const char *label, size_t label_len,
                        unsigned char *output, size_t out_len)
{
    unsigned char prk[KDF_HASH_LEN];
    size_t prk_len;
    int ret;

    /* Validate inputs */
    if (seed == NULL || output == NULL) {
        return KAZ_KDF_ERROR_NULL_PTR;
    }

    if (seed_len == 0 || out_len == 0) {
        return KAZ_KDF_ERROR_INVALID_LEN;
    }

    /* Extract with label as salt */
    ret = kaz_hkdf_extract(
        (const unsigned char *)label, label_len,
        seed, seed_len, prk, &prk_len);

    if (ret != KAZ_KDF_SUCCESS) {
        goto cleanup;
    }

    /* Expand to desired length */
    ret = kaz_hkdf_expand(prk, prk_len, NULL, 0, output, out_len);

cleanup:
    kaz_secure_zero(prk, sizeof(prk));

    return ret;
}
