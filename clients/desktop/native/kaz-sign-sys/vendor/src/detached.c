/*
 * KAZ-SIGN: Detached Signature Implementation
 * Version 3.0
 *
 * Provides detached signing and verification where the signature
 * does not include the original message. Uses SHA-256 hashing
 * internally (zero-padded to level hash_bytes).
 *
 * Detached sign:
 *   1. Hash message with SHA-256 (zero-padded to hash_bytes)
 *   2. Sign the hash using message-recovery mode (kaz_sign_signature_ex)
 *   3. Extract only S1||S2||S3 (discard embedded hash)
 *
 * Detached verify:
 *   1. Hash message with SHA-256 (zero-padded to hash_bytes)
 *   2. Reconstruct full signature as S1||S2||S3||hash
 *   3. Verify using kaz_sign_verify_ex
 *   4. Confirm recovered message matches our hash
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kaz/sign.h"
#include "kaz/security.h"

/* ============================================================================
 * Detached Signature Size
 * ============================================================================ */

size_t kaz_sign_detached_sig_bytes(kaz_sign_level_t level)
{
    const kaz_sign_level_params_t *params = kaz_sign_get_level_params(level);
    if (!params) {
        return 0;
    }
    return params->signature_overhead;
}

/* ============================================================================
 * Detached Sign (from raw message)
 * ============================================================================ */

int kaz_sign_detached_ex(kaz_sign_level_t level,
                         unsigned char *sig,
                         unsigned long long *siglen,
                         const unsigned char *msg,
                         unsigned long long msglen,
                         const unsigned char *sk)
{
    const kaz_sign_level_params_t *params;
    unsigned char *digest = NULL;
    int ret;

    params = kaz_sign_get_level_params(level);
    if (!params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (sig == NULL || siglen == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (msg == NULL && msglen > 0) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Allocate digest buffer */
    digest = malloc(params->hash_bytes);
    if (!digest) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Hash the message with SHA-256 (zero-padded to hash_bytes) */
    ret = kaz_sign_hash_ex(level, msg, msglen, digest);
    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(digest, params->hash_bytes);
        free(digest);
        return ret;
    }

    /* Sign the digest using the prehashed path */
    ret = kaz_sign_detached_prehashed_ex(level, sig, siglen,
                                          digest, params->hash_bytes, sk);

    kaz_secure_zero(digest, params->hash_bytes);
    free(digest);
    return ret;
}

/* ============================================================================
 * Detached Verify (from raw message)
 * ============================================================================ */

int kaz_sign_verify_detached_ex(kaz_sign_level_t level,
                                const unsigned char *sig,
                                unsigned long long siglen,
                                const unsigned char *msg,
                                unsigned long long msglen,
                                const unsigned char *pk)
{
    const kaz_sign_level_params_t *params;
    unsigned char *digest = NULL;
    int ret;

    params = kaz_sign_get_level_params(level);
    if (!params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (sig == NULL || pk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (msg == NULL && msglen > 0) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Allocate digest buffer */
    digest = malloc(params->hash_bytes);
    if (!digest) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Hash the message with SHA-256 (zero-padded to hash_bytes) */
    ret = kaz_sign_hash_ex(level, msg, msglen, digest);
    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(digest, params->hash_bytes);
        free(digest);
        return ret;
    }

    /* Verify using the prehashed path */
    ret = kaz_sign_verify_detached_prehashed_ex(level, sig, siglen,
                                                 digest, params->hash_bytes, pk);

    kaz_secure_zero(digest, params->hash_bytes);
    free(digest);
    return ret;
}

/* ============================================================================
 * Detached Sign (prehashed)
 * ============================================================================ */

/* NOTE: This function hashes the input again internally via kaz_sign_signature_ex.
 * When using the prehashed API, the caller's hash is treated as the "message"
 * which is then hashed again by the signing function. This double-hashing is
 * intentional and consistent with the signature scheme's Fiat-Shamir transform. */
int kaz_sign_detached_prehashed_ex(kaz_sign_level_t level,
                                   unsigned char *sig,
                                   unsigned long long *siglen,
                                   const unsigned char *hash,
                                   unsigned long long hashlen,
                                   const unsigned char *sk)
{
    const kaz_sign_level_params_t *params;
    unsigned char *full_sig = NULL;
    unsigned long long full_siglen = 0;
    int ret;

    params = kaz_sign_get_level_params(level);
    if (!params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (sig == NULL || siglen == NULL || hash == NULL || sk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Validate hash length matches level */
    if (hashlen != params->hash_bytes) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Allocate buffer for full signature (S1||S2||S3||hash) */
    full_sig = malloc(params->signature_overhead + params->hash_bytes);
    if (!full_sig) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Sign the hash as a message using message-recovery mode.
     * This produces: S1||S2||S3||hash (the hash is the "message") */
    ret = kaz_sign_signature_ex(level, full_sig, &full_siglen,
                                 hash, params->hash_bytes, sk);
    if (ret != KAZ_SIGN_SUCCESS) {
        kaz_secure_zero(full_sig, params->signature_overhead + params->hash_bytes);
        free(full_sig);
        return ret;
    }

    /* Guard: inner signing must produce at least signature_overhead bytes */
    if (full_siglen < (unsigned long long)params->signature_overhead) {
        kaz_secure_zero(full_sig, params->signature_overhead + params->hash_bytes);
        free(full_sig);
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Extract only S1||S2||S3 (discard the embedded hash portion) */
    memcpy(sig, full_sig, params->signature_overhead);
    *siglen = params->signature_overhead;

    kaz_secure_zero(full_sig, params->signature_overhead + params->hash_bytes);
    free(full_sig);
    return KAZ_SIGN_SUCCESS;
}

/* ============================================================================
 * Detached Verify (prehashed)
 * ============================================================================ */

int kaz_sign_verify_detached_prehashed_ex(kaz_sign_level_t level,
                                          const unsigned char *sig,
                                          unsigned long long siglen,
                                          const unsigned char *hash,
                                          unsigned long long hashlen,
                                          const unsigned char *pk)
{
    const kaz_sign_level_params_t *params;
    unsigned char *full_sig = NULL;
    unsigned char *recovered_msg = NULL;
    unsigned long long recovered_msglen = 0;
    int ret;

    params = kaz_sign_get_level_params(level);
    if (!params) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    if (sig == NULL || hash == NULL || pk == NULL) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Validate signature length */
    if (siglen != params->signature_overhead) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Validate hash length matches level */
    if (hashlen != params->hash_bytes) {
        return KAZ_SIGN_ERROR_INVALID;
    }

    /* Reconstruct full signature: S1||S2||S3||hash */
    full_sig = malloc(params->signature_overhead + params->hash_bytes);
    if (!full_sig) {
        return KAZ_SIGN_ERROR_MEMORY;
    }

    memcpy(full_sig, sig, params->signature_overhead);
    memcpy(full_sig + params->signature_overhead, hash, params->hash_bytes);

    /* Allocate buffer for recovered message */
    recovered_msg = malloc(params->hash_bytes);
    if (!recovered_msg) {
        kaz_secure_zero(full_sig, params->signature_overhead + params->hash_bytes);
        free(full_sig);
        return KAZ_SIGN_ERROR_MEMORY;
    }

    /* Verify using message-recovery mode */
    ret = kaz_sign_verify_ex(level, recovered_msg, &recovered_msglen,
                              full_sig,
                              params->signature_overhead + params->hash_bytes,
                              pk);

    if (ret != KAZ_SIGN_SUCCESS) {
        goto cleanup;
    }

    /* Confirm recovered message matches our hash */
    if (recovered_msglen != params->hash_bytes) {
        ret = KAZ_SIGN_ERROR_VERIFY;
        goto cleanup;
    }

    if (kaz_ct_memcmp(recovered_msg, hash, params->hash_bytes) != 0) {
        ret = KAZ_SIGN_ERROR_VERIFY;
        goto cleanup;
    }

    ret = KAZ_SIGN_SUCCESS;

cleanup:
    kaz_secure_zero(full_sig, params->signature_overhead + params->hash_bytes);
    free(full_sig);
    kaz_secure_zero(recovered_msg, params->hash_bytes);
    free(recovered_msg);

    return ret;
}
