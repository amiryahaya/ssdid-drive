/*
 * KAZ-SIGN Standalone SHA-256 Implementation
 *
 * Provides one-shot and incremental SHA-256 hashing using OpenSSL EVP.
 * Function names retain kaz_sha3_256 prefix for API compatibility.
 *
 * Aligned with kaz-pqc-jcajce-v2.0 which uses SHA-256 for all levels.
 */

#include "kaz/sign.h"
#include <openssl/evp.h>
#include <stdlib.h>
#include <string.h>

/* SHA-256 output length in bytes */
#define SHA256_DIGEST_LEN 32

/* ============================================================================
 * Internal context structure
 * ============================================================================ */

struct kaz_sha3_ctx_st {
    EVP_MD_CTX *md_ctx;
};

/* ============================================================================
 * One-shot SHA-256 (API-compatible: kaz_sha3_256)
 * ============================================================================ */

int kaz_sha3_256(const unsigned char *msg,
                 unsigned long long msglen,
                 unsigned char *out)
{
    EVP_MD_CTX *ctx = NULL;
    unsigned int out_len = 0;
    int ret = KAZ_SIGN_ERROR_HASH;

    if (out == NULL) {
        return KAZ_SIGN_ERROR_HASH;
    }

    ctx = EVP_MD_CTX_new();
    if (ctx == NULL) {
        return KAZ_SIGN_ERROR_HASH;
    }

    if (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) != 1) {
        goto cleanup;
    }

    if (msg != NULL && msglen > 0) {
        if (msglen > (unsigned long long)SIZE_MAX) {
            goto cleanup;
        }
        if (EVP_DigestUpdate(ctx, msg, (size_t)msglen) != 1) {
            goto cleanup;
        }
    } else if (msg == NULL && msglen == 0) {
        /* Hash of empty message is valid */
    } else if (msg == NULL && msglen > 0) {
        goto cleanup;
    }

    if (EVP_DigestFinal_ex(ctx, out, &out_len) != 1) {
        goto cleanup;
    }

    if (out_len != SHA256_DIGEST_LEN) {
        goto cleanup;
    }

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    EVP_MD_CTX_free(ctx);
    return ret;
}

/* ============================================================================
 * Incremental SHA-256: Init
 * ============================================================================ */

kaz_sha3_ctx_t *kaz_sha3_256_init(void)
{
    kaz_sha3_ctx_t *ctx = malloc(sizeof(kaz_sha3_ctx_t));
    if (ctx == NULL) {
        return NULL;
    }

    ctx->md_ctx = EVP_MD_CTX_new();
    if (ctx->md_ctx == NULL) {
        free(ctx);
        return NULL;
    }

    if (EVP_DigestInit_ex(ctx->md_ctx, EVP_sha256(), NULL) != 1) {
        EVP_MD_CTX_free(ctx->md_ctx);
        free(ctx);
        return NULL;
    }

    return ctx;
}

/* ============================================================================
 * Incremental SHA-256: Update
 * ============================================================================ */

int kaz_sha3_256_update(kaz_sha3_ctx_t *ctx,
                        const unsigned char *data,
                        unsigned long long len)
{
    if (ctx == NULL || ctx->md_ctx == NULL) {
        return KAZ_SIGN_ERROR_HASH;
    }

    if (data == NULL && len > 0) {
        return KAZ_SIGN_ERROR_HASH;
    }

    if (len == 0) {
        return KAZ_SIGN_SUCCESS;
    }

    if (len > (unsigned long long)SIZE_MAX) {
        return KAZ_SIGN_ERROR_HASH;
    }

    if (EVP_DigestUpdate(ctx->md_ctx, data, (size_t)len) != 1) {
        return KAZ_SIGN_ERROR_HASH;
    }

    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Incremental SHA-256: Final
 * ============================================================================ */

int kaz_sha3_256_final(kaz_sha3_ctx_t *ctx,
                       unsigned char *out)
{
    unsigned int out_len = 0;

    if (ctx == NULL || ctx->md_ctx == NULL || out == NULL) {
        return KAZ_SIGN_ERROR_HASH;
    }

    if (EVP_DigestFinal_ex(ctx->md_ctx, out, &out_len) != 1) {
        EVP_MD_CTX_free(ctx->md_ctx);
        ctx->md_ctx = NULL;
        return KAZ_SIGN_ERROR_HASH;
    }

    if (out_len != SHA256_DIGEST_LEN) {
        EVP_MD_CTX_free(ctx->md_ctx);
        ctx->md_ctx = NULL;
        return KAZ_SIGN_ERROR_HASH;
    }

    /* Free internal resources after finalization */
    EVP_MD_CTX_free(ctx->md_ctx);
    ctx->md_ctx = NULL;

    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Incremental SHA-256: Free
 * ============================================================================ */

void kaz_sha3_256_free(kaz_sha3_ctx_t *ctx)
{
    if (ctx == NULL) {
        return;
    }

    if (ctx->md_ctx != NULL) {
        EVP_MD_CTX_free(ctx->md_ctx);
        ctx->md_ctx = NULL;
    }

    free(ctx);
}
